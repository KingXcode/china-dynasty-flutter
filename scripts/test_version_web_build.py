#!/usr/bin/env python3
"""Regression checks for immutable Flutter Web release paths."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from io import BytesIO

from version_web_build import restore_previous, version_build


BOOTSTRAP = '''_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    document.getElementById('loading')?.remove();
  }
});
'''


class VersionWebBuildTest(unittest.TestCase):
    def fixture(self, directory, history='new history'):
        root = Path(directory)
        files = {'index.html': '<script src="flutter_bootstrap.js" async></script>',
                 'flutter_bootstrap.js': BOOTSTRAP, 'main.dart.js': 'new code',
                 'assets/AssetManifest.bin': 'manifest',
                 'assets/assets/history.json': history,
                 'assets/assets/map-data/original.geojson': 'unaltered geometry',
                 'assets/examples/index.html': 'nested HTML asset',
                 'assets/fonts/FontManifest.json': 'font manifest',
                 'canvaskit/canvaskit.js': 'renderer'}
        for name, contents in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        return root, files

    def test_new_release_never_reuses_cached_code_or_data_paths(self):
        with tempfile.TemporaryDirectory() as old, tempfile.TemporaryDirectory() as new:
            old_root, _ = self.fixture(old, 'old history')
            new_root, files = self.fixture(new)
            before, after = version_build(old_root), version_build(new_root)
            self.assertNotEqual(before['version'], after['version'])
            self.assertNotEqual(before['history'], after['history'])
            self.assertIn(after['bootstrap'], (new_root / 'index.html').read_text())
            for name, content in files.items():
                if name not in ('index.html', 'flutter_bootstrap.js'):
                    self.assertEqual((new_root / name).read_text(), content)
                    self.assertEqual((new_root / after['base'] / name).read_text(), content)
            self.assertEqual(version_build(new_root), after)

    def test_loader_and_engine_share_absolute_versioned_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _ = self.fixture(directory)
            result = version_build(root)
            script = (root / result['bootstrap']).read_text()
            harness = '''const assert = require('node:assert/strict');
let loaded, initialized, started = false;
const document = {baseURI: 'https://example.test/china-dynasty-flutter/',
  getElementById: () => ({remove() {}})};
const _flutter = {loader: {load(options) {loaded = options;}}};
''' + script + '''
(async () => {
  await loaded.onEntrypointLoaded({initializeEngine: async (config) => {
    initialized = config; return {runApp: async () => {started = true;}};
  }});
  assert.deepEqual(initialized, loaded.config);
  assert.equal(initialized.assetBase, EXPECTED);
  assert.equal(initialized.entrypointBaseUrl, EXPECTED);
  assert.equal(initialized.canvasKitBaseUrl, EXPECTED + 'canvaskit/');
  assert(started);
})().catch(error => {console.error(error); process.exitCode = 1;});
'''
            harness = harness.replace('EXPECTED', json.dumps(
                'https://example.test/china-dynasty-flutter/' + result['base']))
            subprocess.run(['node', '-e', harness], check=True, capture_output=True)

    def test_changed_processed_build_requires_fresh_flutter_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _ = self.fixture(directory)
            version_build(root)
            (root / 'assets/assets/history.json').write_text('different history')
            with self.assertRaisesRegex(AssertionError, 'Run flutter build web again'):
                version_build(root)

    def test_missing_versioned_asset_cannot_report_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _ = self.fixture(directory)
            result = version_build(root)
            (root / result['history']).unlink()
            with self.assertRaisesRegex(AssertionError, 'Run flutter build web again'):
                version_build(root)

    def test_previous_hashed_page_remains_loadable_after_next_deploy(self):
        with tempfile.TemporaryDirectory() as old, tempfile.TemporaryDirectory() as new:
            old_root, _ = self.fixture(old, 'old history')
            prior = version_build(old_root)
            def download(url, timeout):
                name = url.split('https://example.test/site/', 1)[1].split('?', 1)[0]
                return BytesIO((old_root / name).read_bytes())
            new_root, _ = self.fixture(new)
            with patch('version_web_build.urllib.request.urlopen', side_effect=download):
                retained = restore_previous(new_root, 'https://example.test/site/')
            current = version_build(new_root, retained)
            self.assertEqual((new_root / prior['history']).read_text(), 'old history')
            self.assertEqual((new_root / current['history']).read_text(), 'new history')
            self.assertEqual(current['previous'][0]['version'], prior['version'])


if __name__ == '__main__':
    unittest.main()
