#!/usr/bin/env python3
"""Give each Flutter Web release immutable entrypoint and asset URLs."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import time
import urllib.error
import urllib.request


def restore_previous(root, site):
    """Retain recently superseded builds for cached indexes and open tabs."""
    now = int(time.time())
    try:
        with urllib.request.urlopen(site.rstrip('/') + '/build-version.json?v=' + str(now), timeout=30) as response:
            latest = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:  # First versioned deployment.
            return []
        raise
    prior = [{**latest, 'retired_at': now}, *latest.get('previous', [])]
    retained = []
    seen = set()
    for release in prior:
        if release['version'] in seen or now - release['retired_at'] > 900:
            continue
        seen.add(release['version'])
        assert re.fullmatch(r'builds/[a-f0-9]{20}/', release['base'])
        files = release['files']
        for name, expected in files.items():
            relative = Path(name)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert re.fullmatch(r'[a-f0-9]{64}', expected)
            path = Path(root) / release['base'] / relative
            if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected:
                continue
            with urllib.request.urlopen(site.rstrip('/') + '/' + release['base'] + name, timeout=60) as response:
                content = response.read()
            assert hashlib.sha256(content).hexdigest() == expected, f'Previous release hash mismatch: {name}'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        retained.append({key: value for key, value in release.items() if key != 'previous'})
    return retained


def version_build(root, previous=None):
    root = Path(root)
    bootstrap_path = root / 'flutter_bootstrap.js'
    bootstrap = bootstrap_path.read_text()
    marker = '// HUAXIA_VERSIONED_WEB_BUILD\n'
    manifest_path = root / 'build-version.json'
    if bootstrap.startswith(marker):
        manifest = json.loads(manifest_path.read_text())
        for name, expected in manifest['files'].items():
            for path in (root / name, root / manifest['base'] / name):
                assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected, (
                    f'Processed output changed: {path}. Run flutter build web again.'
                )
        assert f'src="{manifest["bootstrap"]}"' in (root / 'index.html').read_text()
        return manifest
    index = (root / 'index.html').read_text()
    assert index.count('src="flutter_bootstrap.js"') == 1, 'Unexpected HTML entrypoint'
    assert bootstrap.count('_flutter.loader.load({') == 1, 'Unexpected Flutter loader'
    assert bootstrap.count('engineInitializer.initializeEngine()') == 1, 'Unexpected engine callback'
    for required in ('main.dart.js', 'assets/AssetManifest.bin', 'assets/assets/history.json'):
        assert (root / required).is_file(), f'Missing Web output: {required}'

    files = sorted(p for p in root.rglob('*') if p.is_file()
                   and p.relative_to(root).parts[0] != 'builds'
                   and p.name not in ('build-version.json', '.last_build_id'))
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    version = digest.hexdigest()[:20]
    relative = f'builds/{version}/'
    target = root / relative
    target.mkdir(parents=True, exist_ok=True)
    # Preserve original URLs for legacy entrypoints. New pages exclusively use
    # versioned URLs, so cached JSON cannot mix with a newer app.
    for path in files:
        if path.relative_to(root).as_posix() in ('index.html', 'flutter_bootstrap.js', 'flutter_service_worker.js'):
            continue
        destination = target / path.relative_to(root)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
    config = (
        f"const huaxiaBuildBase = new URL('{relative}', document.baseURI).href;\n"
        "const huaxiaWebConfig = {\n"
        "  entrypointBaseUrl: huaxiaBuildBase,\n"
        "  assetBase: huaxiaBuildBase,\n"
        "  canvasKitBaseUrl: new URL('canvaskit/', huaxiaBuildBase).href\n"
        "};\n"
    )
    bootstrap = marker + bootstrap.replace(
        '_flutter.loader.load({', config + '_flutter.loader.load({\n  config: huaxiaWebConfig,',
    ).replace('engineInitializer.initializeEngine()',
              'engineInitializer.initializeEngine(huaxiaWebConfig)')
    (target / 'flutter_bootstrap.js').write_text(bootstrap)
    bootstrap_path.write_text(bootstrap)
    (root / 'index.html').write_text(index.replace(
        'src="flutter_bootstrap.js"', f'src="{relative}flutter_bootstrap.js"',
    ))
    hashes = {path.relative_to(target).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(target.rglob('*')) if path.is_file()}
    manifest = {'version': version, 'base': relative,
                'bootstrap': relative + 'flutter_bootstrap.js',
                'history': relative + 'assets/assets/history.json',
                'files': hashes, 'previous': [p for p in (previous or []) if p['version'] != version]}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
    previous = restore_previous(root, sys.argv[2]) if len(sys.argv) > 2 else []
    result = version_build(root, previous)
    print(json.dumps({key: result[key] for key in ('version', 'base', 'bootstrap', 'history')}))
