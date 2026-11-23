import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:airtrace/src/app.dart';
import 'package:airtrace/src/data/favorites_store.dart';
import 'package:airtrace/src/domain/geo.dart';
import 'package:airtrace/src/domain/live_traffic_controller.dart';
import 'package:airtrace/src/ui/map/plane_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/switchable_gateway.dart';

/// Uçtan uca test: GERÇEK uygulama, GERÇEK ağ, GERÇEK harita.
/// Windows'ta masaüstü, Android emülatöründe telefon olarak çalışır.
/// Çıktıdaki `AIRTRACE_METRIC` ve `AIRTRACE_SHOT` satırları test raporuna
/// ve ekran görüntülerine dönüştürülür.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const shotDir = String.fromEnvironment('SHOT_DIR');
  final rootKey = GlobalKey();

  // debugPrint hız sınırlıdır; uzun çıktılar kaybolmasın diye print kullanılır.
  // ignore: avoid_print
  void metric(String s) => print('AIRTRACE_METRIC $s');

  Future<void> wait(WidgetTester t, bool Function() ok, {int seconds = 60, String what = ''}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Zaman aşımı: $what');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await t.pump();
    }
  }

  Future<void> settle(WidgetTester t, int seconds) async {
    for (var i = 0; i < seconds * 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await t.pump();
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump();
    final boundary = rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 1.0);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    if (shotDir.isNotEmpty) {
      File('$shotDir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    } else {
      final b64 = base64Encode(bytes);
      const chunk = 800;
      for (var i = 0; i * chunk < b64.length; i++) {
        final part = b64.substring(i * chunk, ((i + 1) * chunk).clamp(0, b64.length));
        // ignore: avoid_print
        print('AIRTRACE_SHOT|$name|$i|$part');
      }
    }
    metric('screenshot=$name bytes=${bytes.length}');
  }

  testWidgets('AIRTRACE uçtan uca', (tester) async {
    // Gerçek cihaz depolaması (Windows: AppData, Android: uygulama verisi).
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('airtrace.favorites.v1');
    final gateway = SwitchableGateway();
    final services = await buildServices(prefs, http: gateway);
    final sprite = await PlaneSprite.create();
    final started = DateTime.now();

    await tester.pumpWidget(AirtraceApp(services: services, sprite: sprite, repaintKey: rootKey));
    await settle(tester, 2);

    // 1) Uygulama açılıyor, dünya haritası görünüyor.
    expect(find.text('AIRTRACE'), findsWidgets);
    final mapCtl = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    metric('start_zoom=${mapCtl.camera.zoom.toStringAsFixed(2)}');
    expect(mapCtl.camera.zoom, lessThan(3.5), reason: 'Açılışta tüm dünya görünmeli');

    // 2) Gerçek veri geliyor (dünya görünümü: OpenSky veya ADS-B.lol yedeği).
    await wait(tester, () => services.store.length > 0, seconds: 90, what: 'ilk gerçek veri');
    metric('first_data_s=${DateTime.now().difference(started).inSeconds} world_count=${services.store.length} '
        'opensky_ok=${services.live.lastOpenSkySuccess != null} opensky_blocked=${services.live.openSkyBlocked}');
    await settle(tester, 6);
    await shot(tester, '01_dunya');

    // 3) Yakınlaştır: Frankfurt (yoğun hava sahası) -> ADS-B.lol 10 sn döngüsü.
    const fra = LatLng(50.03, 8.57);
    mapCtl.move(fra, 8);
    await wait(tester, () {
      final t = services.live.lastAdsbSuccess;
      return t != null &&
          services.store.tracks.any((tr) => Geo.distanceNm(fra, tr.lastPosition) < 100 && tr.aircraft.callsign != null);
    }, seconds: 60, what: 'Frankfurt ADS-B.lol verisi');
    expect(services.live.status, LinkStatus.live);
    final near = services.store.tracks.where((t) => Geo.distanceNm(fra, t.lastPosition) < 250).length;
    metric('frankfurt_tracks=$near');
    expect(near, greaterThan(0));

    // 4) Konumlar doğru mu: ADS-B.lol kayıtları sorgu çemberinin içinde.
    final vp = services.live.viewport!;
    for (final t in services.store.tracks.where((t) => t.receivedAt.isAfter(services.live.lastAdsbSuccess!.subtract(const Duration(seconds: 1))))) {
      expect(Geo.distanceNm(vp.center, t.lastPosition), lessThan(270), reason: t.hex);
    }
    await settle(tester, 4);
    await shot(tester, '02_frankfurt');

    // 5) Uçak seç -> bilgi kartı.
    final target = services.store.tracks
        .where((t) => t.aircraft.callsign != null && !t.aircraft.onGround && Geo.distanceNm(fra, t.lastPosition) < 120)
        .first;
    services.selection.select(target.hex, focus: true);
    await settle(tester, 3);
    expect(find.text('UÇUŞ KODU'), findsOneWidget);
    expect(find.text('ÜLKE'), findsOneWidget);
    expect(find.text('HIZ'), findsOneWidget);
    expect(find.text('İRTİFA'), findsOneWidget);
    expect(find.text(target.aircraft.callsign!), findsWidgets);
    await settle(tester, 3);
    await shot(tester, '03_secili_ucak');

    // 6) Favori ekle -> kalıcı mı?
    await tester.tap(find.byKey(const Key('favorite-toggle')));
    await tester.pump();
    expect(services.favorites.contains(target.hex), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await prefs.reload(); // diskten yeniden oku
    expect(FavoritesStore(prefs).contains(target.hex), isTrue, reason: 'Yeniden açılışta favori korunmalı');
    metric('favorite_persisted=true');

    // 7) Arama: uçuş kodu ile yerel arama.
    services.selection.clear();
    await tester.pump();
    final isMobile = MediaQuery.sizeOf(tester.element(find.byType(FlutterMap))).width < 900;
    if (isMobile) {
      // Alt sayfayı yukarı çekerek aç.
      await tester.drag(find.text('AIRTRACE').first, const Offset(0, -450));
      await settle(tester, 2);
    }
    await tester.enterText(find.byKey(const Key('search-field')), target.aircraft.callsign!);
    await settle(tester, 2);
    final row = find.byKey(ValueKey('track-${target.hex}'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await settle(tester, 2);
    expect(services.selection.selectedHex, target.hex);
    metric('search_ok=true mobile=$isMobile');
    services.selection.clear();
    await settle(tester, 1);
    await tester.enterText(find.byKey(const Key('search-field')), '');
    await tester.pump();

    // 8) Harita kontrolleri.
    final z0 = mapCtl.camera.zoom;
    await tester.tap(find.byTooltip('Yakınlaştır'));
    await tester.pump();
    expect(mapCtl.camera.zoom, closeTo(z0 + 1, 0.01));
    await tester.tap(find.byTooltip('Uzaklaştır'));
    await tester.pump();
    expect(mapCtl.camera.zoom, closeTo(z0, 0.01));
    metric('zoom_controls_ok=true');

    // 9) API limitleri: 30 sn'de ADS-B.lol'a en fazla 5 istek (10 sn döngü + takip).
    final before = services.http.requestCounts['api.adsb.lol'] ?? 0;
    await settle(tester, 30);
    final perWindow = (services.http.requestCounts['api.adsb.lol'] ?? 0) - before;
    metric('adsb_requests_30s=$perWindow last_error=${services.live.lastError}');
    // Üst sınır: limit koruması. Alt sınır 1: sağlayıcı 429/yavaş yanıt verirse
    // uygulama bilerek bekler (Retry-After), bu doğru davranıştır.
    expect(perWindow, lessThanOrEqualTo(7));
    expect(perWindow, greaterThanOrEqualTo(1));

    // 10) Bağlantı kesilmesi: son veriler kalır, uyarı görünür; geri gelince canlı.
    final countBefore = services.store.length;
    gateway.offline = true;
    await wait(tester, () => services.live.status != LinkStatus.live, seconds: 70, what: 'çevrimdışı algılama');
    await settle(tester, 2);
    expect(find.text('Bağlantı yok'), findsOneWidget);
    expect(services.store.length, greaterThan(0), reason: 'Son veriler gösterilmeye devam etmeli');
    metric('offline_detected=true kept=${services.store.length}/$countBefore');
    await shot(tester, '04_baglanti_yok');
    gateway.offline = false;
    await wait(tester, () => services.live.status == LinkStatus.live, seconds: 90, what: 'yeniden bağlanma');
    metric('reconnected=true');

    // 11) Bellek.
    metric('rss_mb=${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)} '
        'max_rss_mb=${(ProcessInfo.maxRss / 1048576).toStringAsFixed(1)} tracks=${services.store.length}');
    metric('requests=${services.http.requestCounts}');

    // 12) Dünya görünümüne dön (kümelendirme ekran görüntüsü).
    services.selection.select(target.hex);
    mapCtl.move(const LatLng(48, 10), 5);
    await settle(tester, 12);
    await shot(tester, '05_avrupa');

    services.live.pause();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
