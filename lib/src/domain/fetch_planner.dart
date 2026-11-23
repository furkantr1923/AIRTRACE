import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../data/sources/adsblol_source.dart';
import '../data/sources/opensky_source.dart';

/// Haritanın o an görünen alanı.
class MapViewport {
  const MapViewport({required this.center, required this.radiusNm, required this.box, required this.zoom});

  final LatLng center;

  /// Merkezden en uzak köşeye mesafe (deniz mili).
  final double radiusNm;

  /// Görünen alan kutusu; antimeridyeni aşıyorsa veya çok genişse `null`
  /// (tüm dünya).
  final GeoBox? box;
  final double zoom;

  bool similarTo(MapViewport o) =>
      (zoom - o.zoom).abs() < 0.5 &&
      (center.latitude - o.center.latitude).abs() < radiusNm / 600 &&
      (center.longitude - o.center.longitude).abs() < radiusNm / 600;
}

/// Bir yenileme turunda hangi isteklerin atılacağı.
class FetchPlan {
  const FetchPlan({this.circleCenter, this.circleRadiusNm, this.useOpenSky = false, this.openSkyBox});

  final LatLng? circleCenter;
  final int? circleRadiusNm;
  final bool useOpenSky;
  final GeoBox? openSkyBox;

  bool get useAdsbLol => circleCenter != null;
}

/// Görünüme göre en verimli veri stratejisini seçer.
///
/// * Görünüm 250 nm yarıçapa sığıyorsa: yalnızca ADS-B.lol (hızlı, ayrıntılı).
/// * Daha geniş görünümde: OpenSky sınır kutusu (geniş alan) + görünüm
///   merkezinde ADS-B.lol (merkez bölge canlı kalır).
/// * Kıta/dünya ölçeğinde merkez çemberi anlamsızdır; yalnızca OpenSky.
///   OpenSky kotası doluysa merkez çemberine geri düşülür.
class FetchPlanner {
  const FetchPlanner();

  static const wideOnlyRadiusNm = 1500.0;

  FetchPlan plan(MapViewport v, {required bool openSkyAvailable}) {
    final fitsCircle = v.radiusNm <= AdsbLolSource.maxRadiusNm;
    if (fitsCircle) {
      return FetchPlan(circleCenter: v.center, circleRadiusNm: math.max(5, (v.radiusNm * 1.1).ceil()).clamp(5, 250));
    }
    final box = _expand(v.box);
    if (!openSkyAvailable) {
      return FetchPlan(circleCenter: v.center, circleRadiusNm: AdsbLolSource.maxRadiusNm);
    }
    if (v.radiusNm > wideOnlyRadiusNm) {
      return FetchPlan(useOpenSky: true, openSkyBox: box);
    }
    return FetchPlan(
      circleCenter: v.center,
      circleRadiusNm: AdsbLolSource.maxRadiusNm,
      useOpenSky: true,
      openSkyBox: box,
    );
  }

  static GeoBox? _expand(GeoBox? b) {
    if (b == null) return null;
    final dLat = (b.north - b.south) * 0.08;
    final dLon = (b.east - b.west) * 0.08;
    final west = b.west - dLon, east = b.east + dLon;
    if (west < -180 || east > 180 || east - west >= 300) return null;
    return GeoBox(math.max(-85, b.south - dLat), west, math.min(85, b.north + dLat), east);
  }
}

/// OpenSky kredi bütçesi: günlük kotayı korumak için istek aralığını
/// kalan krediye göre uzatır. Kural: saatte kalan kredinin en fazla
/// %25'i harcanır; asla [minInterval]'dan sık istek atılmaz.
class OpenSkyBudget {
  const OpenSkyBudget();

  static const reserveCredits = 8;

  Duration interval({required int cost, required int? remaining, required int daily, required bool authenticated, DateTime? nowUtc}) {
    final minInterval = Duration(seconds: authenticated ? 20 : 60);
    final rem = remaining ?? daily;
    final calls = (rem - reserveCredits) ~/ cost;
    if (calls <= 0) return untilUtcMidnight(nowUtc ?? DateTime.now().toUtc());
    final perHour = calls / 4.0;
    final seconds = (3600 / perHour).ceil();
    final d = Duration(seconds: seconds);
    return d < minInterval ? minInterval : d;
  }

  static Duration untilUtcMidnight(DateTime nowUtc) {
    final next = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
    return next.difference(nowUtc);
  }
}
