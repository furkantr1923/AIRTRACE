#!/usr/bin/env python3
"""Entegrasyon testi çıktısındaki AIRTRACE_SHOT satırlarını PNG'ye çevirir.

Android'de test süreci dosyayı doğrudan CI'a yazamadığı için ekran görüntüleri
base64 parçaları halinde log'a basılır.
Kullanım: extract_shots.py <log> <çıktı_klasörü>
"""
import base64
import collections
import pathlib
import re
import sys

log, out = sys.argv[1], pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
parts = collections.defaultdict(dict)
try:
    text = open(log, encoding='utf-8', errors='replace').read()
except FileNotFoundError:
    sys.exit(0)
for m in re.finditer(r'AIRTRACE_SHOT\|([\w-]+)\|(\d+)\|([A-Za-z0-9+/=]+)', text):
    parts[m[1]][int(m[2])] = m[3]
for name, chunks in parts.items():
    data = ''.join(chunks[i] for i in sorted(chunks))
    (out / f'{name}.png').write_bytes(base64.b64decode(data))
    print('shot', name, len(data))
