import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class Airport {
  const Airport({
    required this.iata,
    required this.icao,
    required this.name,
    required this.city,
    required this.position,
    required this.country,
  });
  final String iata;
  final String icao;
  final String name;
  final String city;
  final LatLng position;
  final String country;

  String get code => iata.isNotEmpty ? iata : icao;
}

/// Uygulamayla birlikte gelen küçük, çevrimdışı veri setleri (~140 KB).
///
/// * `airports.json`  – OurAirports, tarifeli seferi olan büyük havalimanları.
/// * `airlines.json`  – OpenFlights, aktif havayolları (ICAO kodu -> ad).
/// * `icao_ranges.json` – ICAO Annex 10 Mode-S adres blokları -> ülke (Türkçe).
class StaticData {
  StaticData({
    required this.airports,
    required Map<String, String> airlines,
    required List<IcaoRange> ranges,
  })  : _airlines = airlines,
        _ranges = ranges;

  final List<Airport> airports;
  final Map<String, String> _airlines;
  final List<IcaoRange> _ranges;

  static Future<StaticData> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final results = await Future.wait([
      b.loadString('assets/data/airports.json'),
      b.loadString('assets/data/airlines.json'),
      b.loadString('assets/data/icao_ranges.json'),
    ]);
    return StaticData.fromJson(results[0], results[1], results[2]);
  }

  factory StaticData.fromJson(String airportsJson, String airlinesJson, String rangesJson) {
    final airports = [
      for (final a in jsonDecode(airportsJson) as List<dynamic>)
        if (a is List<dynamic>)
          Airport(
            iata: a[0] as String,
            icao: a[1] as String,
            name: a[2] as String,
            city: a[3] as String,
            position: LatLng((a[4] as num).toDouble(), (a[5] as num).toDouble()),
            country: a[6] as String,
          ),
    ];
    final airlines = (jsonDecode(airlinesJson) as Map<String, dynamic>).cast<String, String>();
    final ranges = [
      for (final r in jsonDecode(rangesJson) as List<dynamic>)
        if (r is List<dynamic>) IcaoRange((r[0] as num).toInt(), (r[1] as num).toInt(), r[2] as String),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return StaticData(airports: airports, airlines: airlines, ranges: ranges);
  }

  String? airlineName(String? icaoPrefix) => icaoPrefix == null ? null : _airlines[icaoPrefix];

  /// ICAO hex adresinin tahsis edildiği ülke. Bloklar iç içe olabildiği için
  /// en dar eşleşme seçilir.
  String? countryForHex(String hex) {
    if (hex.startsWith('~')) return null; // ICAO dışı (TIS-B) adres
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    IcaoRange? best;
    for (final r in _ranges) {
      if (r.start > v) break;
      if (v <= r.end && (best == null || r.size < best.size)) best = r;
    }
    return best?.country;
  }
}

class IcaoRange {
  const IcaoRange(this.start, this.end, this.country);
  final int start;
  final int end;
  final String country;
  int get size => end - start;
}
