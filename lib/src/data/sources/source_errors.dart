/// Veri kaynaklarından gelen hatalar. Arayüz bunları Türkçe mesaja çevirir.
sealed class SourceException implements Exception {
  const SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// İnternet bağlantısı yok veya sunucuya ulaşılamıyor.
class OfflineException extends SourceException {
  const OfflineException([super.message = 'İnternet bağlantısı yok']);
}

/// Sağlayıcı istek limitine ulaşıldı.
class RateLimitedException extends SourceException {
  const RateLimitedException(this.retryAfter, [super.message = 'İstek limiti aşıldı']);
  final Duration retryAfter;
}

/// Sağlayıcı hata döndürdü (5xx, beklenmeyen yanıt).
class ProviderException extends SourceException {
  const ProviderException(super.message, {this.statusCode});
  final int? statusCode;
}

/// Kimlik doğrulama başarısız (OpenSky istemci bilgileri hatalı).
class AuthException extends SourceException {
  const AuthException([super.message = 'OpenSky kimlik bilgileri reddedildi']);
}
