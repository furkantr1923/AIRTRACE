import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/aircraft.dart';
import '../data/static_data.dart';
import 'geo.dart';

/// Bir uçağın oturum boyunca biriken durumu: son gerçek veri + gerçek
/// konumlardan oluşan iz. İzde **hiçbir tahmini nokta yoktur**.
class Track {
  Track(this.aircraft, {required this.country, required this.airlineName, required this.receivedAt, required this.expectedRefresh})
      : trail = [TrailPoint(LatLng(aircraft.lat, aircraft.lon), aircraft.positionTime)];

  Aircraft aircraft;
  String? country;
  String? airlineName;

  /// Bu kaydın en son güncellendiği yerel an.
  DateTime receivedAt;

  /// Bu kaydı sağlayan kaynağın beklenen yenileme aralığı (temizlik için).
  Duration expectedRefresh;
  final List<TrailPoint> trail;

  String get hex => aircraft.hex;
  LatLng get lastPosition => LatLng(aircraft.lat, aircraft.lon);
}

class TrailPoint {
  const TrailPoint(this.position, this.time);
  final LatLng position;
  final DateTime time;
}

/// Canlı trafik deposu. Güncellemeler artımlıdır: yalnızca değişen uçaklar
/// güncellenir, tüm liste yeniden oluşturulmaz.
class TrafficStore extends ChangeNotifier {
  TrafficStore(this._static);

  static const maxTrailPoints = 240;
  static const maxTrailAge = Duration(minutes: 30);
  static const maxTracks = 25000;

  final StaticData _static;
  final Map<String, Track> _tracks = {};

  /// Her değişiklikte artar; çizim katmanı yeniden çizime bununla karar verir.
  int version = 0;

  Iterable<Track> get tracks => _tracks.values;
  int get length => _tracks.length;
  Track? operator [](String hex) => _tracks[hex];
  bool get isEmpty => _tracks.isEmpty;

  String? countryOf(Aircraft a) => _static.countryForHex(a.hex) ?? a.originCountry;
  String? airlineOf(Aircraft a) => _static.airlineName(a.airlineIcao);

  /// Bir veri paketini depoya işler. Aynı uçak için daha eski konumlar
  /// yok sayılır; böylece iki kaynak karışık sırayla gelse de iz geri gitmez.
  /// Değişen kayıt sayısını döndürür.
  int ingest(List<Aircraft> batch, {required Duration expectedRefresh, DateTime? now}) {
    final t = now ?? DateTime.now();
    var changed = 0;
    for (final a in batch) {
      final existing = _tracks[a.hex];
      if (existing == null) {
        if (_tracks.length >= maxTracks) continue;
        _tracks[a.hex] = Track(a,
            country: countryOf(a), airlineName: airlineOf(a), receivedAt: t, expectedRefresh: expectedRefresh);
        changed++;
        continue;
      }
      if (!a.positionTime.isAfter(existing.aircraft.positionTime)) continue;
      final merged = a.mergeIdentity(existing.aircraft);
      final callsignChanged = merged.callsign != existing.aircraft.callsign;
      existing
        ..aircraft = merged
        ..receivedAt = t
        ..expectedRefresh = expectedRefresh;
      if (callsignChanged) existing.airlineName = airlineOf(merged);
      existing.country ??= countryOf(merged);
      final last = existing.trail.last;
      final p = LatLng(merged.lat, merged.lon);
      if (Geo.distanceM(last.position, p) > 30 || merged.positionTime.difference(last.time).inSeconds > 20) {
        existing.trail.add(TrailPoint(p, merged.positionTime));
        if (existing.trail.length > maxTrailPoints) existing.trail.removeAt(0);
      }
      changed++;
    }
    if (changed > 0) {
      version++;
      notifyListeners();
    }
    return changed;
  }

  /// Eski kayıtları kontrollü temizler. Çevrimdışıyken hiçbir şey silinmez:
  /// kullanıcı son bilinen verileri "eski" etiketiyle görmeye devam eder.
  int prune({required bool online, DateTime? now, String? keepHex}) {
    final t = now ?? DateTime.now();
    final cutoffTrail = t.subtract(maxTrailAge);
    final remove = <String>[];
    for (final tr in _tracks.values) {
      while (tr.trail.length > 1 && tr.trail.first.time.isBefore(cutoffTrail)) {
        tr.trail.removeAt(0);
      }
      if (!online || tr.hex == keepHex) continue;
      final ttl = Duration(milliseconds: (tr.expectedRefresh.inMilliseconds * 2.5).round());
      final limit = ttl > const Duration(seconds: 90) ? ttl : const Duration(seconds: 90);
      if (t.difference(tr.receivedAt) > limit) remove.add(tr.hex);
    }
    for (final h in remove) {
      _tracks.remove(h);
    }
    if (remove.isNotEmpty) {
      version++;
      notifyListeners();
    }
    return remove.length;
  }

  void clear() {
    _tracks.clear();
    version++;
    notifyListeners();
  }
}
