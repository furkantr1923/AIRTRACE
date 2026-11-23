import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/interpolation.dart';

/// Seçili uçağın temel bilgileri: uçuş kodu, ülke, hız, irtifa.
/// Masaüstünde sağ panel, Android'de alt kart içinde kullanılır.
class AircraftInfo extends StatefulWidget {
  const AircraftInfo({super.key, this.compact = false});
  final bool compact;

  @override
  State<AircraftInfo> createState() => _AircraftInfoState();
}

class _AircraftInfoState extends State<AircraftInfo> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.selection, s.favorites]),
      builder: (context, _) {
        final t = s.selection.selected;
        final hex = s.selection.selectedHex;
        if (hex == null) return const SizedBox.shrink();
        if (t == null) {
          return _Frame(
            compact: widget.compact,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Header(title: hex.toUpperCase(), subtitle: null, hex: hex),
              const SizedBox(height: 12),
              const Text('Bu uçak şu an canlı veride görünmüyor (yayın kesilmiş veya kapsama dışında olabilir).',
                  style: TextStyle(color: AppColors.textMid, fontSize: 13)),
            ]),
          );
        }
        final a = t.aircraft;
        final dp = const Interpolator().at(a, DateTime.now());
        final route = s.selection.route;
        final tiles = [
          _Tile('Uçuş kodu', a.callsign ?? Fmt.unknown, null),
          _Tile('Ülke', t.country ?? Fmt.unknown, null),
          _Tile('Hız', Fmt.speed(a.groundSpeedMs), Fmt.speedKt(a.groundSpeedMs)),
          _Tile('İrtifa', Fmt.altitude(a.altitudeM, onGround: a.onGround),
              [Fmt.altitudeFt(a.altitudeM, onGround: a.onGround), Fmt.verticalTrend(a.verticalRateMs)].where((e) => e.isNotEmpty).join('  ')),
        ];
        final ident = [a.registration, a.typeCode].whereType<String>().join(' · ');
        return _Frame(
          compact: widget.compact,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Header(title: a.displayName, subtitle: t.airlineName ?? (ident.isEmpty ? null : ident), hex: a.hex),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: widget.compact ? 2.5 : 2.0,
              children: tiles,
            ),
            if (route != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.flight_takeoff, size: 15, color: AppColors.cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Kalkış: ${route.origin.code}  ${route.origin.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Text(
              [
                a.source.label,
                'son gerçek konum ${Fmt.ago(dp.dataAge)}',
                if (dp.isStale) 'veri eski' else if (dp.isPredicted) 'konum tahmini',
              ].join('  ·  '),
              style: TextStyle(fontSize: 11.5, color: dp.isStale ? AppColors.warn : AppColors.textLo),
            ),
          ]),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, required this.compact});
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.all(compact ? 14 : 18), child: child);
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, required this.hex});
  final String title;
  final String? subtitle;
  final String hex;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final fav = s.favorites.contains(hex);
    final t = s.store[hex];
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.electric.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.electric.withValues(alpha: 0.5)),
        ),
        child: const Icon(Icons.flight, color: AppColors.electricBright, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          if (subtitle != null)
            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
        ]),
      ),
      IconButton(
        key: const Key('favorite-toggle'),
        tooltip: fav ? 'Favorilerden çıkar' : 'Favorilere ekle',
        onPressed: t == null && !fav
            ? null
            : () => t != null
                ? s.favorites.toggle(t.aircraft, country: t.country, airline: t.airlineName)
                : s.favorites.remove(hex),
        icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded, color: fav ? AppColors.gold : AppColors.textMid, size: 26),
      ),
      IconButton(
        tooltip: 'Kapat',
        onPressed: s.selection.clear,
        icon: const Icon(Icons.close, size: 20),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.secondary);
  final String label;
  final String value;
  final String? secondary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.anthracite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1.1, color: AppColors.textLo, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (secondary != null && secondary!.isNotEmpty)
            Text(secondary!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.textMid)),
        ]),
      );
}
