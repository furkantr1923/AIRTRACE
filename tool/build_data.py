#!/usr/bin/env python3
"""AIRTRACE statik veri üretici.

Kaynaklar (yerel klonlar, argümanla verilir):
  - OurAirports  airports.csv   (Public Domain)            -> assets/data/airports.json
  - OpenFlights  airlines.dat   (ODbL 1.0)                 -> assets/data/airlines.json
  - ICAO Annex 10 Mode-S adres blokları (tar1090 flags.js derlemesi) -> assets/data/icao_ranges.json
Ülke adları Türkçe: Unicode CLDR (babel).

Kullanım: python3 tool/build_data.py <airports.csv> <airlines.dat> <flags.js> <çıktı_klasörü>
"""
import csv, json, re, sys
from babel import Locale

TR = Locale('tr').territories
FIX = {'TR': 'Türkiye'}

def tr_country(code: str) -> str:
    code = (code or '').upper()
    return FIX.get(code) or TR.get(code) or code

def airports(path):
    out = []
    for r in csv.DictReader(open(path, encoding='utf-8')):
        if r['type'] != 'large_airport' or r['scheduled_service'] != 'yes':
            continue
        out.append([
            r['iata_code'] or '', r['icao_code'] or r['gps_code'] or r['ident'],
            r['name'], r['municipality'] or '',
            round(float(r['latitude_deg']), 4), round(float(r['longitude_deg']), 4),
            tr_country(r['iso_country']),
        ])
    out.sort(key=lambda a: a[1])
    return out

def airlines(path):
    out = {}
    for row in csv.reader(open(path, encoding='utf-8'), escapechar='\\'):
        if len(row) < 8:
            continue
        name, icao, callsign, active = row[1], row[4], row[5], row[7]
        if active != 'Y' or not re.fullmatch(r'[A-Z]{3}', icao or ''):
            continue
        out.setdefault(icao, name.strip())
    return dict(sorted(out.items()))

def ranges(path):
    txt = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r'start:\s*0x([0-9A-Fa-f]+),\s*end:\s*0x([0-9A-Fa-f]+),\s*country:\s*"[^"]*",\s*country_code:\s*"([a-z]{2})"', txt):
        out.append([int(m[1], 16), int(m[2], 16), tr_country(m[3])])
    out.sort()
    return out

if __name__ == '__main__':
    a, l, f, dst = sys.argv[1:5]
    for name, data in (('airports', airports(a)), ('airlines', airlines(l)), ('icao_ranges', ranges(f))):
        with open(f'{dst}/{name}.json', 'w', encoding='utf-8') as fh:
            json.dump(data, fh, ensure_ascii=False, separators=(',', ':'))
        print(name, len(data))
