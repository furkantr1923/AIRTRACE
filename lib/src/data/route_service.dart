import 'package:latlong2/latlong.dart';

import 'sources/http_gateway.dart';

class RouteAirport {
  const RouteAirport(this.code, this.name, this.position);
  final String code;
  final String name;
  final LatLng position;
}

/// Seçili uçağın kalkış/varış bilgisi.
///
/// ADS-B.lol rota servisi, uçuş koduna göre bilinen rotayı döndürür ve uçağın
/// gerçek konumunun bu rotayla uyumlu olup olmadığını `plausible` alanıyla
/// bildirir. AIRTRACE rotayı **yalnızca plausible=true** ise çizer.
class FlightRoute {
  const FlightRoute(this.airports);
  final List<RouteAirport> airports;
  RouteAirport get origin => airports.first;
  RouteAirport get destination => airports.last;
}

class RouteService {
  RouteService(this._http, {Uri? baseUri}) : _base = baseUri ?? Uri.parse('https://api.adsb.lol');

  final HttpGateway _http;
  final Uri _base;
  final Map<String, FlightRoute?> _cache = {};

  /// Güvenilir rota yoksa `null` döner. Hatalar sessizce `null`'a çevrilir:
  /// rota isteğe bağlı bir bilgidir, ana akışı bozmamalıdır.
  Future<FlightRoute?> lookup(String callsign, LatLng position) async {
    final key = callsign.toUpperCase();
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final res = await _http.postJson(_base.replace(path: '/api/0/routeset'), {
        'planes': [
          {'callsign': key, 'lat': position.latitude, 'lng': position.longitude},
        ],
      });
      final route = parse(res.body);
      _cache[key] = route;
      return route;
    } catch (_) {
      return null;
    }
  }

  static FlightRoute? parse(Object? body) {
    if (body is! List || body.isEmpty) return null;
    final r = body.first;
    if (r is! Map<String, dynamic> || r['plausible'] != true) return null;
    final list = r['_airports'];
    if (list is! List || list.length < 2) return null;
    final airports = <RouteAirport>[];
    for (final a in list) {
      if (a is! Map<String, dynamic>) return null;
      final lat = asDouble(a['lat']);
      final lon = asDouble(a['lon']);
      if (lat == null || lon == null) return null;
      airports.add(RouteAirport(
        asTrimmed(a['iata']) ?? asTrimmed(a['icao']) ?? '?',
        asTrimmed(a['name']) ?? '',
        LatLng(lat, lon),
      ));
    }
    return FlightRoute(airports);
  }
}
