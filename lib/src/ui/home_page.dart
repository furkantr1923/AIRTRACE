import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import 'map/air_map.dart';
import 'map/plane_sprite.dart';
import 'map/traffic_layer.dart';
import 'widgets/about_sheet.dart';
import 'widgets/aircraft_info.dart';
import 'widgets/aircraft_panel.dart';
import 'widgets/map_controls.dart';
import 'widgets/status_bar.dart';

/// Ana ekran. Genişliğe göre iki düzen:
/// * Masaüstü (≥ 900 px): sol liste · orta harita · sağ bilgi paneli.
/// * Mobil: tam ekran harita · alttan açılan liste · seçili uçak kartı.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.sprite});
  final PlaneSprite sprite;

  static const desktopBreakpoint = 900.0;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _map = MapController();
  final _frameClock = FrameClock();
  final _sheet = DraggableScrollableController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    s.selection.onFocus = (target, minZoom) {
      final z = _map.camera.zoom;
      _map.move(target, minZoom == null ? z : math.max(z, minZoom));
    };
    s.live.start();
    // Arka planda / simge durumunda: veri isteği ve çizim durur.
    _lifecycle = AppLifecycleListener(
      onHide: _pause,
      onPause: _pause,
      onShow: _resume,
      onResume: _resume,
    );
  }

  void _pause() {
    final s = AppScope.of(context);
    s.live.pause();
    _frameClock.active = false;
  }

  void _resume() {
    final s = AppScope.of(context);
    _frameClock.active = true;
    s.live.start();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _frameClock.dispose();
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= HomePage.desktopBreakpoint;
    return Scaffold(body: wide ? _desktop() : _mobile());
  }

  Widget _brand({bool compact = false}) => Row(children: [
        const Icon(Icons.radar, color: AppColors.electric, size: 22),
        const SizedBox(width: 8),
        const Text('AIRTRACE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 16)),
        const Spacer(),
        IconButton(
          tooltip: 'Hakkında ve ayarlar',
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => AboutSheet.show(context),
        ),
      ]);

  Widget _mapStack({required bool wide}) => Stack(children: [
        Positioned.fill(child: AirMap(controller: _map, sprite: widget.sprite, frameClock: _frameClock)),
        Positioned(
          left: 12,
          top: 12,
          right: wide ? 80 : 12,
          child: SafeArea(child: Align(alignment: Alignment.topLeft, child: StatusBar(compact: !wide))),
        ),
        Positioned(
          right: 12,
          bottom: wide ? 36 : null,
          top: wide ? null : 110,
          child: SafeArea(child: MapControls(controller: _map)),
        ),
      ]);

  Widget _desktop() {
    final s = AppScope.of(context);
    return Row(children: [
      Container(
        width: 340,
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(right: BorderSide(color: AppColors.stroke)),
        ),
        child: SafeArea(child: AircraftPanel(header: Padding(padding: const EdgeInsets.only(bottom: 10), child: _brand()))),
      ),
      Expanded(child: _mapStack(wide: true)),
      ListenableBuilder(
        listenable: s.selection,
        builder: (context, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: s.selection.selectedHex == null ? 0 : 340,
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(left: BorderSide(color: AppColors.stroke)),
          ),
          child: s.selection.selectedHex == null
              ? null
              // Genişlik animasyonu sırasında içerik sıkışmasın diye sabit genişlikte
              // çizilip kırpılır.
              : const ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 340,
                    maxWidth: 340,
                    child: SingleChildScrollView(child: AircraftInfo()),
                  ),
                ),
        ),
      ),
    ]);
  }

  Widget _mobile() {
    final s = AppScope.of(context);
    return Stack(children: [
      Positioned.fill(child: _mapStack(wide: false)),
      ListenableBuilder(
        listenable: s.selection,
        builder: (context, _) {
          if (s.selection.selectedHex != null) {
            return Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.stroke),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 6))],
                  ),
                  child: const AircraftInfo(compact: true),
                ),
              ),
            );
          }
          return DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: 0.17,
            minChildSize: 0.17,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.17, 0.5, 0.88],
            builder: (context, scroll) => Container(
              decoration: const BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 18)],
              ),
              child: AircraftPanel(
                scrollController: scroll,
                onPicked: () {
                  if (_sheet.isAttached) _sheet.jumpTo(0.17);
                },
                header: Column(children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: AppColors.stroke, borderRadius: BorderRadius.circular(2)),
                  ),
                  _brand(compact: true),
                ]),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
