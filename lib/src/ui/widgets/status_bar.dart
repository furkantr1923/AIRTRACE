import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/live_traffic_controller.dart';

/// Bağlantı durumu, son güncelleme zamanı ve uçak sayısı. Veri eskiyse veya
/// bağlantı yoksa bunu açıkça söyler; canlı veri varmış gibi davranmaz.
class StatusBar extends StatefulWidget {
  const StatusBar({super.key, this.compact = false});
  final bool compact;

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
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
    final live = s.live;
    final status = live.status;
    final (color, label) = switch (status) {
      LinkStatus.connecting => (AppColors.electric, 'Bağlanıyor…'),
      LinkStatus.live => (AppColors.ok, 'Canlı'),
      LinkStatus.stale => (AppColors.warn, 'Veriler eski'),
      LinkStatus.offline => (AppColors.danger, 'Bağlantı yok'),
    };
    final last = live.lastSuccess;
    final parts = <String>[
      if (last != null) 'Son güncelleme ${Fmt.clock(last)} (${Fmt.ago(DateTime.now().difference(last))})',
      '${Fmt.count(s.store.length)} uçak',
      if (!widget.compact) _sources(live),
    ];

    String? notice;
    if (status == LinkStatus.offline) {
      notice = s.store.isEmpty
          ? 'İnternet bağlantısı yok. Bağlantı gelince veriler otomatik yüklenecek.'
          : 'Bağlantı kesildi. Gösterilen konumlar son alınan verilerdir; otomatik yeniden deneniyor.';
    } else if (status == LinkStatus.stale && live.lastError != null) {
      notice = '${live.lastError}. Otomatik yeniden deneniyor.';
    } else if (live.openSkyBlocked && live.usingAdsb) {
      final wait = Fmt.duration(live.openSkyBlockedUntil!.difference(DateTime.now()));
      notice = live.openSkyQuotaExhausted
          ? 'OpenSky günlük kotası doldu; geniş alan verisi $wait sonra. Harita merkezi (~460 km) ADS-B.lol ile canlı.'
          : 'Geniş alan kaynağına (OpenSky) şu an ulaşılamıyor; $wait sonra yeniden denenecek. '
              'Harita merkezi (~460 km) ADS-B.lol ile canlı.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pill(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(color: color, pulse: status == LinkStatus.live),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                parts.join('  ·  '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMid, fontSize: 12),
              ),
            ),
          ]),
        ),
        if (notice != null) ...[
          const SizedBox(height: 6),
          _Pill(
            border: color.withValues(alpha: 0.6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.info_outline, size: 15, color: color),
              const SizedBox(width: 8),
              Flexible(child: Text(notice, style: const TextStyle(fontSize: 12, color: AppColors.textHi))),
              if (status == LinkStatus.offline || status == LinkStatus.stale) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: live.retryNow,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Şimdi dene'),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  static String _sources(LiveTrafficController live) {
    final src = [if (live.usingAdsb) 'ADS-B.lol', if (live.usingOpenSky) 'OpenSky'];
    return src.isEmpty ? '' : 'Kaynak: ${src.join(' + ')}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.border});
  final Widget child;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border ?? AppColors.stroke),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: child,
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: pulse ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
        ),
      );
}
