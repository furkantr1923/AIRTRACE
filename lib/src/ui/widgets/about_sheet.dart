import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/theme.dart';

/// Veri kaynakları, limitler, lisanslar ve isteğe bağlı OpenSky hesabı.
class AboutSheet extends StatefulWidget {
  const AboutSheet({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => const Dialog(
          insetPadding: EdgeInsets.all(20),
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560, maxHeight: 720), child: AboutSheet()),
        ),
      );

  @override
  State<AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<AboutSheet> {
  late final TextEditingController _id;
  late final TextEditingController _secret;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    _id = TextEditingController(text: s.settings.openSkyClientId ?? '');
    _secret = TextEditingController(text: s.settings.openSkyClientSecret ?? '');
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await s.settings.setOpenSkyCredentials(_id.text, _secret.text);
    s.openSkyCredentialsChanged();
    nav.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(s.live.openSky.isAuthenticated
          ? 'OpenSky hesabı kaydedildi (günlük 4.000 kredi).'
          : 'OpenSky anonim modda (günlük 400 kredi).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const h = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.electricBright, letterSpacing: 0.6);
    const p = TextStyle(fontSize: 12.5, color: AppColors.textMid, height: 1.45);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.radar, color: AppColors.electric),
          SizedBox(width: 10),
          Text('AIRTRACE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2)),
          SizedBox(width: 8),
          Text('v1.0.0', style: TextStyle(color: AppColors.textLo)),
        ]),
        const SizedBox(height: 16),
        const Text('KAPSAMA HAKKINDA', style: h),
        const SizedBox(height: 6),
        const Text(
          'AIRTRACE yalnızca gerçek ADS-B/MLAT verisi gösterir; sahte veya rastgele uçak üretmez. '
          'Bazı uçaklar görünmeyebilir: ADS-B yayını yapmayan uçaklar, gönüllü alıcıların bulunmadığı '
          'bölgeler (okyanuslar, bazı ülkeler) ve gizlilik programlarındaki (LADD/PIA) uçaklar.',
          style: p,
        ),
        const SizedBox(height: 16),
        const Text('VERİ KAYNAKLARI VE LİMİTLER', style: h),
        const SizedBox(height: 6),
        const Text(
          '• ADS-B.lol — ücretsiz, anahtarsız. Yakın görünümde 10 sn\'de bir, en fazla 250 deniz mili '
          'yarıçap. Limitler sunucu yüküne göre dinamiktir. Veriler ODbL 1.0 lisanslıdır.\n'
          '• OpenSky Network — geniş (kıta/dünya) görünüm için. Anonim: günde 400 kredi; ücretsiz hesapla '
          '4.000 kredi. Dünya sorgusu 4 kredi. Kota korunması için istek aralığı kalan krediye göre '
          'otomatik uzatılır. Yalnızca kişisel/ticari olmayan kullanım.\n'
          '• Uygulama arka plandayken hiçbir istek gönderilmez.',
          style: p,
        ),
        const SizedBox(height: 16),
        const Text('OPENSKY HESABI (İSTEĞE BAĞLI)', style: h),
        const SizedBox(height: 6),
        const Text(
          'opensky-network.org üzerinde ücretsiz hesap açıp "API Client" oluşturursanız geniş görünüm '
          'daha sık yenilenir. Bilgiler yalnızca bu cihazda saklanır.',
          style: p,
        ),
        const SizedBox(height: 10),
        TextField(controller: _id, decoration: const InputDecoration(labelText: 'Client ID')),
        const SizedBox(height: 8),
        TextField(
          controller: _secret,
          obscureText: _hide,
          decoration: InputDecoration(
            labelText: 'Client Secret',
            suffixIcon: IconButton(
              tooltip: _hide ? 'Göster' : 'Gizle',
              icon: Icon(_hide ? Icons.visibility : Icons.visibility_off, size: 18),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('LİSANS VE ATIFLAR', style: h),
        const SizedBox(height: 6),
        const Text(
          'Harita: © OpenStreetMap katkıcıları (ODbL), © CARTO (Dark Matter).\n'
          'Uçak verisi: ADS-B.lol (ODbL 1.0), The OpenSky Network (opensky-network.org).\n'
          'Havalimanları: OurAirports (kamu malı). Havayolları: OpenFlights (ODbL 1.0).\n'
          'Ülke adları: Unicode CLDR. Harita motoru: flutter_map (BSD-3).',
          style: p,
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('Kaydet')),
        ]),
      ]),
    );
  }
}
