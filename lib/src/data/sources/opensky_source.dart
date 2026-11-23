import '../models/aircraft.dart';
import 'http_gateway.dart';
import 'source_errors.dart';

/// Coğrafi sınır kutusu (derece). `null` = tüm dünya.
class GeoBox {
  const GeoBox(this.south, this.west, this.north, this.east);
  final double south, west, north, east;

  /// Kare derece cinsinden alan (OpenSky kredi hesabı bununla yapılır).
  double get areaSqDeg => (north - south).abs() * (east - west).abs();
}

/// OpenSky Network REST istemcisi (https://opensky-network.org).
///
/// Ücretsiz kullanım koşulları (kişisel / araştırma, ticari olmayan):
/// * Anonim: günde 400 kredi, 10 sn zaman çözünürlüğü.
/// * Ücretsiz hesap (OAuth2 client credentials): günde 4000 kredi.
/// * Bir `/states/all` isteğinin maliyeti alana göre 1–4 kredidir.
///
/// İstemci bilgileri kaynak koduna gömülmez; kullanıcı isterse Ayarlar'dan
/// girer ve yalnızca cihazda saklanır.
class OpenSkySource {
  OpenSkySource(this._http, {Uri? baseUri, Uri? tokenUri})
      : _base = baseUri ?? Uri.parse('https://opensky-network.org'),
        _tokenUri = tokenUri ??
            Uri.parse('https://auth.opensky-network.org/auth/realms/opensky-network/'
                'protocol/openid-connect/token');

  static const anonymousDailyCredits = 400;
  static const authenticatedDailyCredits = 4000;

  final HttpGateway _http;
  final Uri _base;
  final Uri _tokenUri;

  String? _clientId;
  String? _clientSecret;
  String? _token;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Son yanıttan okunan kalan kredi (bilinmiyorsa null).
  int? remainingCredits;

  bool get isAuthenticated => _clientId != null && _clientSecret != null;
  int get dailyCredits => isAuthenticated ? authenticatedDailyCredits : anonymousDailyCredits;

  void setCredentials(String? clientId, String? clientSecret) {
    final id = clientId?.trim();
    final secret = clientSecret?.trim();
    final valid = id != null && id.isNotEmpty && secret != null && secret.isNotEmpty;
    _clientId = valid ? id : null;
    _clientSecret = valid ? secret : null;
    _token = null;
    remainingCredits = null;
  }

  /// OpenSky kredi tablosu.
  static int creditCost(GeoBox? box) {
    if (box == null) return 4;
    final a = box.areaSqDeg;
    if (a <= 25) return 1;
    if (a <= 100) return 2;
    if (a <= 400) return 3;
    return 4;
  }

  Future<List<Aircraft>> fetchStates(GeoBox? box) async {
    final query = box == null
        ? null
        : {
            'lamin': box.south.toStringAsFixed(3),
            'lomin': box.west.toStringAsFixed(3),
            'lamax': box.north.toStringAsFixed(3),
            'lomax': box.east.toStringAsFixed(3),
          };
    final uri = _base.replace(path: '/api/states/all', queryParameters: query);
    final headers = <String, String>{};
    if (isAuthenticated) {
      headers['Authorization'] = 'Bearer ${await _accessToken()}';
    }
    final res = await _http.getJson(uri, headers: headers);
    remainingCredits = int.tryParse(res.headers['x-rate-limit-remaining'] ?? '') ?? remainingCredits;
    return parse(res.body);
  }

  Future<String> _accessToken() async {
    final now = DateTime.now();
    if (_token != null && now.isBefore(_tokenExpiry)) return _token!;
    final GatewayResponse res;
    try {
      res = await _http.postForm(_tokenUri, {
        'grant_type': 'client_credentials',
        'client_id': _clientId!,
        'client_secret': _clientSecret!,
      });
    } on ProviderException {
      throw const AuthException();
    }
    final body = res.body;
    if (body is! Map<String, dynamic> || body['access_token'] is! String) {
      throw const AuthException();
    }
    _token = body['access_token'] as String;
    final ttl = (body['expires_in'] as num?)?.toInt() ?? 1800;
    _tokenExpiry = now.add(Duration(seconds: ttl - 60));
    return _token!;
  }

  /// `states` dizisini ayrıştırır. Alan sırası OpenSky belgelerindeki
  /// state vector tanımıyla aynıdır.
  static List<Aircraft> parse(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const ProviderException('OpenSky beklenmeyen yanıt döndürdü');
    }
    final time = (body['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final states = body['states'];
    if (states is! List) return const [];

    final out = <Aircraft>[];
    for (final s in states) {
      if (s is! List || s.length < 17) continue;
      final hex = asTrimmed(s[0]);
      final lon = asDouble(s[5]);
      final lat = asDouble(s[6]);
      final tPos = (s[3] as num?)?.toInt();
      if (hex == null || lat == null || lon == null || tPos == null) continue;
      if (time - tPos > 60) continue;
      final onGround = s[8] == true;
      out.add(Aircraft(
        hex: hex.toLowerCase(),
        lat: lat,
        lon: lon,
        positionTime: DateTime.fromMillisecondsSinceEpoch(tPos * 1000, isUtc: true),
        source: DataSource.openSky,
        callsign: asTrimmed(s[1])?.toUpperCase(),
        originCountry: asTrimmed(s[2]),
        altitudeM: onGround ? null : (asDouble(s[7]) ?? asDouble(s[13])),
        onGround: onGround,
        groundSpeedMs: asDouble(s[9]),
        trackDeg: asDouble(s[10]),
        verticalRateMs: asDouble(s[11]),
        squawk: asTrimmed(s[14]),
      ));
    }
    return out;
  }
}
