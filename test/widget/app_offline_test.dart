import 'package:airtrace/src/app.dart';
import 'package:airtrace/src/ui/map/air_map.dart';
import 'package:airtrace/src/ui/map/plane_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/switchable_gateway.dart';

/// İnternet yokken: boş harita + açık bağlantı uyarısı; sahte uçak yok.
void main() {
  setUp(() {
    AirMap.tilesEnabled = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> run(WidgetTester tester, Size size, {required bool desktop}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    // Büyük asset'ler compute() ile çözüldüğü için gerçek async bölgede yükle.
    final services = (await tester.runAsync(() => buildServices(prefs, http: SwitchableGateway(offline: true))))!;
    final sprite = (await tester.runAsync(PlaneSprite.create))!;
    await tester.pumpWidget(AirtraceApp(services: services, sprite: sprite));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('AIRTRACE'), findsWidgets);
    expect(find.text('Bağlantı yok'), findsOneWidget);
    expect(find.textContaining('İnternet bağlantısı yok'), findsOneWidget);
    expect(services.store.isEmpty, isTrue, reason: 'Veri yokken uçak üretilmemeli');
    expect(find.byTooltip('Yakınlaştır'), findsOneWidget);
    expect(find.byTooltip('Uzaklaştır'), findsOneWidget);
    expect(find.byTooltip('Konumuma dön'), findsOneWidget);
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    services.live.pause();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('masaüstü düzeni çevrimdışı', (tester) => run(tester, const Size(1400, 900), desktop: true));
  testWidgets('mobil düzen çevrimdışı', (tester) => run(tester, const Size(400, 820), desktop: false));
}
