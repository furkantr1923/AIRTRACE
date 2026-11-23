import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_scope.dart';
import '../../core/theme.dart';
import '../../data/favorites_store.dart';
import '../../domain/clustering.dart';
import '../../domain/interpolation.dart';
import '../../domain/selection_controller.dart';
import '../../domain/traffic_store.dart';
import 'plane_sprite.dart';

/// Yakınlaştırmaya göre çizim sıklığını ayarlayan saat. Uzak görünümde
/// uçaklar ekranda neredeyse hareket etmediği için saniyede 1 kare yeter;
/// yakın görünümde akıcılık için 30 kareye çıkar. Arka planda tamamen durur.
class FrameClock extends ChangeNotifier {
  Timer? _timer;
  Duration _interval = const Duration(seconds: 1);
  bool _active = true;

  void configure({required double zoom}) {
    final next = zoom >= 9
        ? const Duration(milliseconds: 33)
        : zoom >= 7
            ? const Duration(milliseconds: 66)
            : zoom >= 4.5
                ? const Duration(milliseconds: 250)
                : const Duration(seconds: 1);
    if (next == _interval && (_timer != null || !_active)) return;
    _interval = next;
    _restart();
  }

  set active(bool v) {
    if (v == _active) return;
    _active = v;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = _active ? Timer.periodic(_interval, (_) => notifyListeners()) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Son çizilen karedeki dokunulabilir öğeler (harita tıklaması için).
class HitIndex {
  final List<String> hexes = [];
  final List<Offset> points = [];
  final List<Offset> clusterCenters = [];
  final List<int> clusterCounts = [];

  void reset() {
    hexes.clear();
    points.clear();
    clusterCenters.clear();
    clusterCounts.clear();
  }

  /// Dokunulan noktaya en yakın uçak (veya küme). [radius] piksel.
  ({String? hex, Offset? cluster}) query(Offset tap, {double radius = 22}) {
    String? best;
    var bestD = radius * radius;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - tap).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = hexes[i];
      }
    }
    if (best != null) return (hex: best, cluster: null);
    for (final c in clusterCenters) {
      if ((c - tap).distance < 26) return (hex: null, cluster: c);
    }
    return (hex: null, cluster: null);
  }
}

class TrafficLayer extends StatelessWidget {
  const TrafficLayer({super.key, required this.sprite, required this.clock, required this.hitIndex});

  final PlaneSprite sprite;
  final FrameClock clock;
  final HitIndex hitIndex;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final s = AppScope.of(context);
    clock.configure(zoom: camera.zoom);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrafficPainter(
              camera: camera,
              store: s.store,
              selection: s.selection,
              favorites: s.favorites,
              sprite: sprite,
              hitIndex: hitIndex,
              repaint: Listenable.merge([clock, s.store, s.selection, s.favorites]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({
    required this.camera,
    required this.store,
    required this.selection,
    required this.favorites,
    required this.sprite,
    required this.hitIndex,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapCamera camera;
  final TrafficStore store;
  final SelectionController selection;
  final FavoritesStore favorites;
  final PlaneSprite sprite;
  final HitIndex hitIndex;

  static const _interp = Interpolator();
  static final _clusterer = GridClusterer();
  static final Map<String, TextPainter> _labelCache = {};
  static final Map<int, TextPainter> _countCache = {};

  static const _cAir = AppColors.electric;
  static const _cGround = AppColors.ground;
  static const _cFav = AppColors.gold;
  static const _cSel = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    hitIndex.reset();
    final now = DateTime.now();
    final zoom = camera.zoom;
    final origin = camera.pixelOrigin;
    final worldW = camera.getWorldWidthAtZoom();
    const margin = 30.0;
    final selHex = selection.selectedHex;

    // 1) Görünür uçakları topla (tahmini konumlarıyla).
    final pts = <Offset>[];
    final tracks = <Track>[];
    final dps = <DisplayPosition>[];
    Offset? selPoint;
    DisplayPosition? selDp;
    Track? selTrack;

    for (final t in store.tracks) {
      final dp = _interp.at(t.aircraft, now);
      final p = camera.projectAtZoom(dp.position) - origin;
      for (final x in _worldCopies(p.dx, size.width, worldW, margin)) {
        if (p.dy < -margin || p.dy > size.height + margin) break;
        final q = Offset(x, p.dy);
        if (t.hex == selHex) {
          selPoint = q;
          selDp = dp;
          selTrack = t;
          continue;
        }
        pts.add(q);
        tracks.add(t);
        dps.add(dp);
      }
    }

    // 2) Kümelendirme: uzak görünümde ve yoğun bölgelerde. Favoriler kümeye
    //    girmez, her zaman görünür kalır.
    List<int> singles;
    List<Cluster> clusters = const [];
    if (zoom < 6.5 && pts.length > 250) {
      final favIdx = <int>[];
      final otherIdx = <int>[];
      for (var i = 0; i < tracks.length; i++) {
        (favorites.contains(tracks[i].hex) ? favIdx : otherIdx).add(i);
      }
      final r = _clusterer.run([for (final i in otherIdx) pts[i]]);
      singles = [for (final i in r.singles) otherIdx[i], ...favIdx];
      clusters = r.clusters;
    } else {
      singles = List<int>.generate(pts.length, (i) => i);
    }

    // 3) Kısa hareket izleri (yalnızca gerçek konumlar) – yakın görünümde.
    if (zoom >= 7 && singles.length <= 600) {
      final trailPaint = Paint()
        ..color = AppColors.electric.withValues(alpha: 0.28)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (final i in singles) {
        final tr = tracks[i].trail;
        if (tr.length < 2) continue;
        final path = Path();
        final start = math.max(0, tr.length - 6);
        final dx = pts[i].dx - (camera.projectAtZoom(dps[i].position) - origin).dx;
        for (var k = start; k < tr.length; k++) {
          final o = camera.projectAtZoom(tr[k].position) - origin + Offset(dx, 0);
          k == start ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        path.lineTo(pts[i].dx, pts[i].dy);
        canvas.drawPath(path, trailPaint);
      }
    }

    // 4) Seçili uçağın rotası ve izi (daha belirgin).
    if (selTrack != null && selPoint != null && selDp != null) {
      _paintSelectedPath(canvas, selTrack, selPoint, selDp, origin);
    }

    // 5) Uçaklar: tek atlas çağrısı.
    final n = singles.length + (selPoint != null ? 1 : 0);
    if (n > 0) {
      final xf = Float32List(n * 4);
      final rects = Float32List(n * 4);
      final colors = Int32List(n);
      final base = zoom < 4 ? 11.0 : zoom < 6 ? 14.0 : zoom < 8 ? 18.0 : 22.0;
      var j = 0;
      void put(Offset at, Track t, DisplayPosition dp, Color color, double px) {
        final tf = atlasTransform(at, t.aircraft.trackDeg ?? 0, px / PlaneSprite.size);
        xf[j * 4] = tf.scos;
        xf[j * 4 + 1] = tf.ssin;
        xf[j * 4 + 2] = tf.tx;
        xf[j * 4 + 3] = tf.ty;
        rects[j * 4] = 0;
        rects[j * 4 + 1] = 0;
        rects[j * 4 + 2] = PlaneSprite.size;
        rects[j * 4 + 3] = PlaneSprite.size;
        final c = dp.isStale ? color.withValues(alpha: 0.38) : color;
        colors[j] = c.toARGB32();
        j++;
      }

      for (final i in singles) {
        final t = tracks[i];
        final color = favorites.contains(t.hex)
            ? _cFav
            : t.aircraft.onGround
                ? _cGround
                : _cAir;
        put(pts[i], t, dps[i], color, t.aircraft.onGround ? base * 0.8 : base);
        hitIndex.hexes.add(t.hex);
        hitIndex.points.add(pts[i]);
      }
      if (selPoint != null) {
        canvas.drawCircle(
          selPoint,
          base * 1.05,
          Paint()
            ..color = AppColors.electric.withValues(alpha: 0.22)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          selPoint,
          base * 1.05,
          Paint()
            ..color = AppColors.electricBright
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        put(selPoint, selTrack!, selDp!, _cSel, base * 1.3);
        hitIndex.hexes.add(selTrack.hex);
        hitIndex.points.add(selPoint);
      }
      canvas.drawRawAtlas(
        sprite.image,
        xf,
        rects,
        colors,
        BlendMode.modulate,
        null,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // 6) Küme balonları.
    if (clusters.isNotEmpty) {
      final fill = Paint()..color = AppColors.electric.withValues(alpha: 0.20);
      final stroke = Paint()
        ..color = AppColors.electric.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final c in clusters) {
        final r = 10 + math.min(14.0, math.log(c.count) * 2.6);
        canvas.drawCircle(c.center, r, fill);
        canvas.drawCircle(c.center, r, stroke);
        final tp = _countLabel(c.count);
        tp.paint(canvas, c.center - Offset(tp.width / 2, tp.height / 2));
        hitIndex.clusterCenters.add(c.center);
        hitIndex.clusterCounts.add(c.count);
      }
    }

    // 7) Uçuş kodu etiketleri: yalnızca yakın görünümde ve makul yoğunlukta.
    final showLabels = zoom >= 7.5 || (zoom >= 6 && singles.length <= 120);
    if (showLabels && singles.length <= 350) {
      for (final i in singles) {
        final tp = _label(tracks[i].aircraft.displayName);
        tp.paint(canvas, pts[i] + const Offset(11, -18));
      }
    }
    if (selPoint != null && selTrack != null) {
      final tp = _label(selTrack.aircraft.displayName, selected: true);
      final o = selPoint + const Offset(16, -22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 5, o.dy - 2, tp.width + 10, tp.height + 4), const Radius.circular(4)),
        Paint()..color = AppColors.electric,
      );
      tp.paint(canvas, o);
    }
  }

  void _paintSelectedPath(Canvas canvas, Track t, Offset at, DisplayPosition dp, Offset origin) {
    final shift = at.dx - (camera.projectAtZoom(dp.position) - origin).dx;
    Offset proj(LatLng p) => camera.projectAtZoom(p) - origin + Offset(shift, 0);

    // Güvenilir rota (yalnızca plausible=true geldiyse): kalkış -> mevcut konum.
    final route = selection.route;
    if (route != null) {
      final from = route.origin.position;
      final path = Path();
      const steps = 48;
      for (var k = 0; k <= steps; k++) {
        final f = k / steps;
        final p = _gcInterpolate(from, dp.position, f);
        final o = proj(p);
        k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      final o = proj(from);
      canvas.drawCircle(o, 4, Paint()..color = AppColors.cyan);
      final tp = _label(route.origin.code);
      tp.paint(canvas, o + const Offset(7, -7));
    }

    // Gerçek iz (düz çizgi) + son gerçek konumdan tahmini konuma (kesikli).
    final tr = t.trail;
    if (tr.isNotEmpty) {
      final path = Path();
      for (var k = 0; k < tr.length; k++) {
        final o = proj(tr[k].position);
        k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.electricBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      );
      if (dp.isPredicted) {
        _dashed(canvas, proj(tr.last.position), at, Paint()
          ..color = AppColors.electricBright.withValues(alpha: 0.8)
          ..strokeWidth = 1.6);
      }
    }
  }

  static LatLng _gcInterpolate(LatLng a, LatLng b, double f) {
    final lat1 = a.latitudeInRad, lon1 = a.longitudeInRad;
    final lat2 = b.latitudeInRad, lon2 = b.longitudeInRad;
    final d = 2 *
        math.asin(math.sqrt(math.pow(math.sin((lat2 - lat1) / 2), 2) +
            math.cos(lat1) * math.cos(lat2) * math.pow(math.sin((lon2 - lon1) / 2), 2)));
    if (d < 1e-9) return a;
    final A = math.sin((1 - f) * d) / math.sin(d);
    final B = math.sin(f * d) / math.sin(d);
    final x = A * math.cos(lat1) * math.cos(lon1) + B * math.cos(lat2) * math.cos(lon2);
    final y = A * math.cos(lat1) * math.sin(lon1) + B * math.cos(lat2) * math.sin(lon2);
    final z = A * math.sin(lat1) + B * math.sin(lat2);
    final lat = math.atan2(z, math.sqrt(x * x + y * y));
    final lon = math.atan2(y, x);
    return LatLng(lat * 180 / math.pi, lon * 180 / math.pi);
  }

  static void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    for (double s = 0; s < total; s += 7) {
      c.drawLine(a + dir * s, a + dir * math.min(s + 3.5, total), p);
    }
  }

  /// Dünya tekrar ettiğinde (yatay kaydırma) aynı uçağın görünen kopyaları.
  static Iterable<double> _worldCopies(double x, double width, double worldW, double margin) sync* {
    if (worldW <= 0) {
      if (x >= -margin && x <= width + margin) yield x;
      return;
    }
    final kMin = ((-margin - x) / worldW).ceil();
    final kMax = ((width + margin - x) / worldW).floor();
    for (var k = kMin; k <= kMax; k++) {
      yield x + k * worldW;
    }
  }

  static TextPainter _label(String text, {bool selected = false}) {
    final key = selected ? '\u0001$text' : text;
    final cached = _labelCache[key];
    if (cached != null) return cached;
    if (_labelCache.length > 3000) _labelCache.clear();
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.textHi.withValues(alpha: 0.85),
          fontSize: selected ? 12 : 10.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.3,
          shadows: selected ? null : const [Shadow(color: Color(0xFF000000), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _labelCache[key] = tp;
  }

  static TextPainter _countLabel(int n) {
    final key = n > 999 ? 1000 + (n ~/ 100) * 100 : n;
    return _countCache[key] ??= (TextPainter(
      text: TextSpan(
        text: n > 999 ? '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}B' : '$n',
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  @override
  bool shouldRepaint(_TrafficPainter old) => old.camera != camera;
}

