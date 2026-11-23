import 'dart:io';

import 'package:airtrace/src/data/models/aircraft.dart';
import 'package:airtrace/src/data/static_data.dart';

/// Testlerde uygulamayla birlikte gelen gerçek statik veriler kullanılır.
StaticData loadStaticData() => StaticData.fromJson(
      File('assets/data/airports.json').readAsStringSync(),
      File('assets/data/airlines.json').readAsStringSync(),
      File('assets/data/icao_ranges.json').readAsStringSync(),
    );

/// Yalnızca birim testleri için elle oluşturulmuş kayıt (uygulamada asla
/// kullanılmaz).
Aircraft testAircraft({
  String hex = '4bb1a1',
  String? callsign = 'THY4KJ',
  double lat = 41.0,
  double lon = 29.0,
  DateTime? time,
  double? speed = 230,
  double? track = 90,
  double? alt = 10000,
  bool onGround = false,
  DataSource source = DataSource.adsbLol,
}) =>
    Aircraft(
      hex: hex,
      callsign: callsign,
      lat: lat,
      lon: lon,
      positionTime: time ?? DateTime.utc(2026, 1, 1, 12),
      source: source,
      groundSpeedMs: speed,
      trackDeg: track,
      altitudeM: alt,
      onGround: onGround,
    );
