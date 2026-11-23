import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Küresel geometri yardımcıları (WGS84 küre yaklaşımı).
abstract final class Geo {
  static const earthRadiusM = 6371008.8;
  static const metersPerNm = 1852.0;

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;

  /// İki nokta arası büyük daire mesafesi (m).
  static double distanceM(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double distanceNm(LatLng a, LatLng b) => distanceM(a, b) / metersPerNm;

  /// Başlangıç noktasından verilen rota (derece) ve mesafe (m) ile varılan
  /// nokta. Ara değerleme (dead reckoning) için kullanılır.
  static LatLng destination(LatLng start, double bearingDeg, double distanceM) {
    final d = distanceM / earthRadiusM;
    final b = _rad(bearingDeg);
    final lat1 = _rad(start.latitude);
    final lon1 = _rad(start.longitude);
    final lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b));
    final lon2 = lon1 +
        math.atan2(math.sin(b) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
    return LatLng(_deg(lat2).clamp(-90.0, 90.0), normalizeLon(_deg(lon2)));
  }

  static double normalizeLon(double lon) {
    var l = (lon + 180) % 360;
    if (l < 0) l += 360;
    return l - 180;
  }
}
