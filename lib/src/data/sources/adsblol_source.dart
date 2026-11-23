import 'package:latlong2/latlong.dart';

import '../models/aircraft.dart';
import 'http_gateway.dart';
import 'source_errors.dart';

/// ADS-B.lol açık API istemcisi (https://api.adsb.lol).
///
/// * Anahtar gerektirmez, ücretsizdir. Veriler ODbL 1.0 lisanslıdır.
/// * Nokta sorgusu en fazla 250 deniz mili yarıçap destekler.
/// * Limitler sunucu yüküne göre dinamiktir; uygulama bu yüzden 10 sn'den
///   sık istek göndermez.
class AdsbLolSource {
  AdsbLolSource(this._http, {Uri? baseUri}) : _base = baseUri ?? Uri.parse('https://api.adsb.lol');

  static const maxRadiusNm = 250;
  static const _ftToM = 0.3048;
  static const _ktToMs = 0.514444;
  static const _fpmToMs = 0.00508;

  final HttpGateway _http;
  final Uri _base;

  Future<List<Aircraft>> fetchCircle(LatLng center, int radiusNm) async {
    final r = radiusNm.clamp(1, maxRadiusNm);
    final uri = _base.replace(
      path: '/v2/point/${center.latitude.toStringAsFixed(4)}/'
          '${center.longitude.toStringAsFixed(4)}/$r',
    );
    return parse((await _http.getJson(uri)).body);
  }

  Future<List<Aircraft>> fetchByHex(String hex) =>
      _byPath('/v2/hex/${Uri.encodeComponent(hex.toLowerCase())}');

  Future<List<Aircraft>> fetchByCallsign(String callsign) =>
      _byPath('/v2/callsign/${Uri.encodeComponent(callsign.toUpperCase())}');

  Future<List<Aircraft>> fetchByRegistration(String reg) =>
      _byPath('/v2/registration/${Uri.encodeComponent(reg.toUpperCase())}');

  Future<List<Aircraft>> _byPath(String path) async =>
      parse((await _http.getJson(_base.replace(path: path))).body);

  /// ADSBExchange v2 uyumlu yanıtı ayrıştırır. Konumu olmayan veya 60 sn'den
  /// eski konumlu kayıtlar atlanır.
  static List<Aircraft> parse(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const ProviderException('ADS-B.lol beklenmeyen yanıt döndürdü');
    }
    final nowMs = (body['now'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final list = body['ac'];
    if (list is! List) return const [];

    final out = <Aircraft>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final lat = asDouble(item['lat']);
      final lon = asDouble(item['lon']);
      final hex = asTrimmed(item['hex']);
      if (lat == null || lon == null || hex == null) continue;
      if (lat.abs() > 90 || lon.abs() > 180) continue;

      final seenPos = asDouble(item['seen_pos']) ?? asDouble(item['seen']) ?? 0;
      if (seenPos > 60) continue;

      final altRaw = item['alt_baro'];
      final onGround = altRaw == 'ground';
      final altFt = altRaw is num ? altRaw.toDouble() : asDouble(item['alt_geom']);

      out.add(Aircraft(
        hex: hex.toLowerCase(),
        lat: lat,
        lon: lon,
        positionTime: DateTime.fromMillisecondsSinceEpoch(nowMs - (seenPos * 1000).round(), isUtc: true),
        source: DataSource.adsbLol,
        callsign: asTrimmed(item['flight'])?.toUpperCase(),
        registration: asTrimmed(item['r']),
        typeCode: asTrimmed(item['t']),
        altitudeM: onGround || altFt == null ? null : altFt * _ftToM,
        onGround: onGround,
        groundSpeedMs: _mul(asDouble(item['gs']), _ktToMs),
        trackDeg: asDouble(item['track']) ?? asDouble(item['true_heading']),
        verticalRateMs: _mul(asDouble(item['baro_rate']) ?? asDouble(item['geom_rate']), _fpmToMs),
        squawk: asTrimmed(item['squawk']),
      ));
    }
    return out;
  }

  static double? _mul(double? v, double k) => v == null ? null : v * k;
}
