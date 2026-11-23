import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Tek bir beyaz uçak silueti doku atlası. Tüm uçaklar tek `drawRawAtlas`
/// çağrısıyla, renk ve dönüş bilgisiyle GPU'ya gönderilir; binlerce uçakta
/// bile widget veya path yeniden oluşturulmaz.
class PlaneSprite {
  PlaneSprite._(this.image);

  static const size = 64.0;
  static const anchor = Offset(size / 2, size / 2);
  final ui.Image image;

  static Future<PlaneSprite> create() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawPath(planePath(size), Paint()..color = const Color(0xFFFFFFFF)..isAntiAlias = true);
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    return PlaneSprite._(img);
  }

  /// Burnu yukarı (kuzey) bakan sade uçak silueti.
  static Path planePath(double s) {
    final u = s / 64;
    return Path()
      ..moveTo(32 * u, 3 * u)
      ..cubicTo(35 * u, 3 * u, 36 * u, 8 * u, 36 * u, 13 * u)
      ..lineTo(36 * u, 24 * u)
      ..lineTo(60 * u, 37 * u)
      ..lineTo(60 * u, 43 * u)
      ..lineTo(36 * u, 36 * u)
      ..lineTo(35 * u, 50 * u)
      ..lineTo(43 * u, 56 * u)
      ..lineTo(43 * u, 60 * u)
      ..lineTo(32 * u, 57 * u)
      ..lineTo(21 * u, 60 * u)
      ..lineTo(21 * u, 56 * u)
      ..lineTo(29 * u, 50 * u)
      ..lineTo(28 * u, 36 * u)
      ..lineTo(4 * u, 43 * u)
      ..lineTo(4 * u, 37 * u)
      ..lineTo(28 * u, 24 * u)
      ..lineTo(28 * u, 13 * u)
      ..cubicTo(28 * u, 8 * u, 29 * u, 3 * u, 32 * u, 3 * u)
      ..close();
  }
}

/// `drawRawAtlas` için RSTransform değerleri. [trackDeg] kuzeyden saat
/// yönünde derece; ekran koordinatlarında y aşağı doğru olduğu için pozitif
/// açı saat yönünde döndürür, yani 90° = doğu.
({double scos, double ssin, double tx, double ty}) atlasTransform(Offset at, double trackDeg, double scale) {
  final r = trackDeg * math.pi / 180;
  final scos = math.cos(r) * scale;
  final ssin = math.sin(r) * scale;
  const ax = PlaneSprite.size / 2, ay = PlaneSprite.size / 2;
  return (
    scos: scos,
    ssin: ssin,
    tx: at.dx - scos * ax + ssin * ay,
    ty: at.dy - ssin * ax - scos * ay,
  );
}
