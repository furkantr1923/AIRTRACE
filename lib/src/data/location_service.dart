import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationOutcome { ok, denied, deniedForever, serviceOff, error }

/// Konum yalnızca kullanıcı "Konumuma dön" veya yakınlık sıralamasını
/// istediğinde sorulur. İzin verilmezse uygulama konumsuz çalışmaya devam eder.
class LocationService extends ChangeNotifier {
  LatLng? lastKnown;
  LocationOutcome? lastOutcome;

  Future<LocationOutcome> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _set(LocationOutcome.serviceOff);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return _set(LocationOutcome.denied);
      if (perm == LocationPermission.deniedForever) return _set(LocationOutcome.deniedForever);
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      lastKnown = LatLng(p.latitude, p.longitude);
      return _set(LocationOutcome.ok);
    } catch (_) {
      return _set(LocationOutcome.error);
    }
  }

  LocationOutcome _set(LocationOutcome o) {
    lastOutcome = o;
    notifyListeners();
    return o;
  }

  static String message(LocationOutcome o) => switch (o) {
        LocationOutcome.ok => 'Konum bulundu',
        LocationOutcome.denied => 'Konum izni verilmedi. AIRTRACE konumsuz çalışmaya devam ediyor.',
        LocationOutcome.deniedForever => 'Konum izni kalıcı olarak kapalı. Sistem ayarlarından açabilirsiniz.',
        LocationOutcome.serviceOff => 'Cihazın konum servisi kapalı.',
        LocationOutcome.error => 'Konum alınamadı.',
      };
}
