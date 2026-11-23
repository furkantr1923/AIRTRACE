import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/route_service.dart';
import 'live_traffic_controller.dart';
import 'traffic_store.dart';

typedef FocusHandler = void Function(LatLng target, double? minZoom);

/// Seçili uçak, güvenilir rotası ve haritayı odaklama istekleri.
class SelectionController extends ChangeNotifier {
  SelectionController({required this.store, required this.live, required this.routes});

  final TrafficStore store;
  final LiveTrafficController live;
  final RouteService routes;

  String? _hex;
  FlightRoute? route;

  /// Harita widget'ı kendini buraya bağlar.
  FocusHandler? onFocus;

  String? get selectedHex => _hex;
  Track? get selected => _hex == null ? null : store[_hex!];

  void select(String? hex, {bool focus = false}) {
    if (hex == _hex) {
      if (focus) _focusSelected();
      return;
    }
    _hex = hex;
    route = null;
    live.followHex = hex;
    notifyListeners();
    if (hex == null) return;
    if (focus) _focusSelected();
    unawaited(_loadRoute(hex));
  }

  void clear() => select(null);

  void focusOn(LatLng p, {double? minZoom}) => onFocus?.call(p, minZoom);

  void _focusSelected() {
    final t = selected;
    if (t != null) onFocus?.call(t.lastPosition, 7);
  }

  Future<void> _loadRoute(String hex) async {
    final t = store[hex];
    final cs = t?.aircraft.callsign;
    if (t == null || cs == null || t.aircraft.onGround) return;
    final r = await routes.lookup(cs, t.lastPosition);
    if (_hex != hex) return;
    route = r;
    notifyListeners();
  }
}
