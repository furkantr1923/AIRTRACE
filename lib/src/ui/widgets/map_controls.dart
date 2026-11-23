import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app_scope.dart';
import '../../core/theme.dart';
import '../../data/location_service.dart';

/// Yalnızca üç kontrol: yakınlaştır, uzaklaştır, konumuma dön.
class MapControls extends StatefulWidget {
  const MapControls({super.key, required this.controller});
  final MapController controller;

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _locating = false;

  void _zoom(double delta) {
    final cam = widget.controller.camera;
    widget.controller.move(cam.center, (cam.zoom + delta).clamp(1.0, 14.0));
  }

  Future<void> _locate() async {
    if (_locating) return;
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final outcome = await s.location.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    final p = s.location.lastKnown;
    if (outcome == LocationOutcome.ok && p != null) {
      widget.controller.move(p, math.max(widget.controller.camera.zoom, 8));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(LocationService.message(outcome))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _Btn(icon: Icons.add, tooltip: 'Yakınlaştır', onTap: () => _zoom(1)),
        const _Sep(),
        _Btn(icon: Icons.remove, tooltip: 'Uzaklaştır', onTap: () => _zoom(-1)),
        const _Sep(),
        _Btn(
          icon: Icons.my_location,
          tooltip: 'Konumuma dön',
          onTap: _locate,
          busy: _locating,
        ),
      ]),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(width: 28, height: 1, color: AppColors.stroke);
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.tooltip, required this.onTap, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, color: AppColors.textHi, size: 21, semanticLabel: tooltip),
            ),
          ),
        ),
      );
}
