#!/usr/bin/env python3
"""Verify original data assets against the preserved source manifest."""
import hashlib, json, pathlib
root=pathlib.Path(__file__).resolve().parent.parent
folder=root/'assets/map-data'
manifest=json.loads((folder/'manifest.json').read_text())
for name, expected in manifest['files'].items():
 actual=hashlib.sha256((folder/name).read_bytes()).hexdigest()
 assert actual==expected, f'{name}: source bytes changed'
data=json.loads((root/'assets/history.json').read_text())
assert len(data['dynasties'])==102
assert len(data['sources'])==56
assert len(data['eras'])==13
print(f"PASS: {len(manifest['files'])} map files preserve original SHA-256; complete timeline data")
