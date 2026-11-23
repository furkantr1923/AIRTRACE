import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/theme.dart';
import '../../data/static_data.dart';

/// Büyük uluslararası havalimanları. Uzak görünümde gizli, orta yakınlıkta
/// nokta, yakın görünümde kod ve ad gösterilir; harita kalabalıklaşmaz.
class AirportLayer extends StatelessWidget {
  const AirportLayer({super.key, required this.airports});
  final List<Airport> airports;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < 3.5) return const SizedBox.shrink();
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _AirportPainter(camera, airports)),
      ),
    );
  }
}

class _AirportPainter extends CustomPainter {
  _AirportPainter(this.camera, this.airports);
  final MapCamera camera;
  final List<Airport> airports;

  static final Map<String, TextPainter> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = camera.zoom;
    final origin = camera.pixelOrigin;
    final worldW = camera.getWorldWidthAtZoom();
    final dot = Paint()..color = AppColors.navyMid;
    final ring = Paint()
      ..color = AppColors.cyan.withValues(alpha: zoom < 5 ? 0.5 : 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final r = zoom < 5 ? 2.2 : zoom < 7 ? 3.0 : 4.0;
    final showCode = zoom >= 6;
    final showName = zoom >= 9;

    for (final a in airports) {
      var p = camera.projectAtZoom(a.position) - origin;
      if (worldW > 0) {
        while (p.dx < -20) {
          p = p.translate(worldW, 0);
        }
        while (p.dx > size.width + 20) {
          p = p.translate(-worldW, 0);
        }
      }
      if (p.dx < -20 || p.dy < -20 || p.dx > size.width + 20 || p.dy > size.height + 20) continue;
      canvas.drawCircle(p, r, dot);
      canvas.drawCircle(p, r, ring);
      if (showCode) {
        final tp = _text(showName ? '${a.code}  ${a.name}' : a.code, big: showName);
        tp.paint(canvas, p + Offset(r + 4, -tp.height / 2));
      }
    }
  }

  static TextPainter _text(String s, {required bool big}) => _cache[s] ??= (TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: AppColors.cyan.withValues(alpha: 0.9),
            fontSize: big ? 11 : 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 260));

  @override
  bool shouldRepaint(_AirportPainter old) => old.camera != camera;
}
