import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'source_errors.dart';

/// Tüm ağ isteklerinin geçtiği tek kapı.
///
/// * Zaman aşımı ve hata eşlemesini tek yerde yapar.
/// * İstek sayılarını host bazında sayar (API limit testleri ve tanılama için).
/// * Hiçbir yanıt gövdesini veya kimlik bilgisini loglamaz.
class HttpGateway {
  HttpGateway({http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client();

  static const userAgent = 'AIRTRACE/1.0 (+https://github.com/furkantr1923/AIRTRACE)';

  final http.Client _client;
  final Duration timeout;
  final Map<String, int> _requestCounts = {};

  /// Host -> şimdiye kadar gönderilen istek sayısı.
  Map<String, int> get requestCounts => Map.unmodifiable(_requestCounts);

  Future<GatewayResponse> getJson(Uri uri, {Map<String, String>? headers}) =>
      _send(() => _client.get(uri, headers: _headers(headers)), uri);

  Future<GatewayResponse> postJson(Uri uri, Object body, {Map<String, String>? headers}) => _send(
        () => _client.post(
          uri,
          headers: _headers({'Content-Type': 'application/json', ...?headers}),
          body: jsonEncode(body),
        ),
        uri,
      );

  Future<GatewayResponse> postForm(Uri uri, Map<String, String> form) => _send(
        () => _client.post(uri, headers: _headers(null), body: form),
        uri,
      );

  Map<String, String> _headers(Map<String, String>? extra) => {
        'User-Agent': userAgent,
        'Accept': 'application/json',
        ...?extra,
      };

  Future<GatewayResponse> _send(Future<http.Response> Function() request, Uri uri) async {
    _requestCounts.update(uri.host, (v) => v + 1, ifAbsent: () => 1);
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on SocketException {
      throw const OfflineException();
    } on TimeoutException {
      // Zaman aşımı genellikle sağlayıcı yoğunluğudur; bağlantı kopukluğu
      // (SocketException) ayrıca yakalanır.
      throw const ProviderException('Veri sağlayıcısı zamanında yanıt vermedi');
    } on HandshakeException {
      throw const OfflineException('Güvenli bağlantı kurulamadı');
    } on http.ClientException {
      throw const OfflineException();
    }

    if (res.statusCode == 429) {
      final retry = int.tryParse(res.headers['x-rate-limit-retry-after-seconds'] ?? '') ??
          int.tryParse(res.headers['retry-after'] ?? '') ??
          60;
      throw RateLimitedException(Duration(seconds: retry.clamp(5, 86400)));
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw ProviderException('Erişim reddedildi (${res.statusCode})', statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ProviderException('Sağlayıcı hatası (${res.statusCode})', statusCode: res.statusCode);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const ProviderException('Sağlayıcı geçersiz yanıt döndürdü');
    }
    return GatewayResponse(decoded, res.headers);
  }

  void close() => _client.close();
}

class GatewayResponse {
  const GatewayResponse(this.body, this.headers);
  final Object? body;
  final Map<String, String> headers;
}

/// JSON yardımcıları: sayısal alanlar int veya double gelebilir.
double? asDouble(Object? v) => v is num ? v.toDouble() : null;
String? asTrimmed(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
