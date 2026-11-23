import 'package:latlong2/latlong.dart';

import 'geo.dart';
import 'traffic_store.dart';

enum SortMode {
  nearest('Yakınlık'),
  callsign('Uçuş kodu'),
  airline('Havayolu'),
  speed('Hız'),
  altitude('İrtifa');

  const SortMode(this.label);
  final String label;
}

/// Listeyi sıralar. [reference] kullanıcı konumu (izin varsa) veya harita
/// merkezidir; yakınlık sıralaması bu noktaya göre yapılır.
List<Track> sortTracks(List<Track> tracks, SortMode mode, {LatLng? reference}) {
  final list = List<Track>.of(tracks);
  int byName(Track a, Track b) => a.aircraft.displayName.compareTo(b.aircraft.displayName);
  switch (mode) {
    case SortMode.nearest:
      if (reference == null) {
        list.sort(byName);
        break;
      }
      final d = {for (final t in list) t.hex: Geo.distanceM(reference, t.lastPosition)};
      list.sort((a, b) => d[a.hex]!.compareTo(d[b.hex]!));
    case SortMode.callsign:
      list.sort(byName);
    case SortMode.airline:
      list.sort((a, b) {
        final c = (a.airlineName ?? '\u{FFFF}').compareTo(b.airlineName ?? '\u{FFFF}');
        return c != 0 ? c : byName(a, b);
      });
    case SortMode.speed:
      list.sort((a, b) => (b.aircraft.groundSpeedMs ?? -1).compareTo(a.aircraft.groundSpeedMs ?? -1));
    case SortMode.altitude:
      list.sort((a, b) => (b.aircraft.altitudeM ?? -1).compareTo(a.aircraft.altitudeM ?? -1));
  }
  return list;
}
