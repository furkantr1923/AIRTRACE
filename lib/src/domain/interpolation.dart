import 'package:latlong2/latlong.dart';

import '../data/models/aircraft.dart';
import 'geo.dart';

/// Ekranda gösterilecek konum. [isPredicted] true ise konum gerçek ölçüm
/// değil, son gerçek konumdan hız ve rotayla hesaplanmış tahmindir.
class DisplayPosition {
  const DisplayPosition(this.position, {required this.isPredicted, required this.dataAge, required this.isStale});
  final LatLng position;
  final bool isPredicted;

  /// Son gerçek konumun yaşı.
  final Duration dataAge;

  /// Veri [Interpolator.maxPrediction]'dan eski: tahmin durdurulmuştur ve
  /// arayüz uçağı soluk gösterir.
  final bool isStale;
}

/// Kontrollü ara değerleme: yeni veri gelene kadar uçak son bilinen hız ve
/// rotasıyla düz ilerletilir. Tahmin süresi sınırlıdır; sınır aşılırsa uçak
/// son tahmin edilen noktada durur ve "eski veri" olarak işaretlenir.
class Interpolator {
  const Interpolator({this.maxPrediction = const Duration(seconds: 60), this.minSpeedMs = 5});

  final Duration maxPrediction;
  final double minSpeedMs;

  DisplayPosition at(Aircraft a, DateTime now) {
    final real = LatLng(a.lat, a.lon);
    var age = now.difference(a.positionTime);
    if (age.isNegative) age = Duration.zero;
    final stale = age > maxPrediction;

    final speed = a.groundSpeedMs;
    final track = a.trackDeg;
    if (a.onGround || speed == null || track == null || speed < minSpeedMs) {
      return DisplayPosition(real, isPredicted: false, dataAge: age, isStale: stale);
    }
    final dt = (stale ? maxPrediction : age).inMilliseconds / 1000.0;
    if (dt < 0.25) return DisplayPosition(real, isPredicted: false, dataAge: age, isStale: false);
    return DisplayPosition(
      Geo.destination(real, track, speed * dt),
      isPredicted: true,
      dataAge: age,
      isStale: stale,
    );
  }
}
