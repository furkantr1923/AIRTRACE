/// Türkçe birim ve zaman biçimlendirme. Bilinmeyen değerler için uydurma
/// yapılmaz, "Bilinmiyor" döner.
abstract final class Fmt {
  static const unknown = 'Bilinmiyor';

  static String _group(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String count(int v) => _group(v);

  /// m/s -> "845 km/sa".
  static String speed(double? ms) => ms == null ? unknown : '${_group((ms * 3.6).round())} km/sa';

  /// m/s -> "456 kt".
  static String speedKt(double? ms) => ms == null ? '' : '${_group((ms / 0.514444).round())} kt';

  static String altitude(double? m, {bool onGround = false}) {
    if (onGround) return 'Yerde';
    if (m == null) return unknown;
    return '${_group((m / 10).round() * 10)} m';
  }

  static String altitudeFt(double? m, {bool onGround = false}) {
    if (onGround || m == null) return '';
    return '${_group((m / 0.3048 / 100).round() * 100)} ft';
  }

  static String verticalTrend(double? ms) {
    if (ms == null || ms.abs() < 1) return '';
    return ms > 0 ? '↑ tırmanıyor' : '↓ alçalıyor';
  }

  static String ago(Duration d) {
    final s = d.inSeconds;
    if (s < 5) return 'şimdi';
    if (s < 60) return '$s sn önce';
    if (s < 3600) return '${d.inMinutes} dk önce';
    return '${d.inHours} sa önce';
  }

  static String clock(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  static String distanceKm(double meters) {
    final km = meters / 1000;
    return km < 10 ? '${km.toStringAsFixed(1).replaceAll('.', ',')} km' : '${_group(km.round())} km';
  }

  static String duration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    if (d.inMinutes >= 1) return '${d.inMinutes} dk';
    return '${d.inSeconds} sn';
  }
}
