@Tags(['live'])
library;

import 'dart:io';

import 'package:airtrace/src/data/models/aircraft.dart';
import 'package:airtrace/src/data/sources/adsblol_source.dart';
import 'package:airtrace/src/data/sources/http_gateway.dart';
import 'package:airtrace/src/data/sources/opensky_source.dart';
import 'package:airtrace/src/data/sources/source_errors.dart';
import 'package:airtrace/src/domain/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// GERÇEK ağ testleri: sağlayıcılara gerçek istek atar. CI'da çalıştırılır.
void main() {
  // flutter_test HTTP isteklerini varsayılan olarak 400 ile engeller.
  setUpAll(() => HttpOverrides.global = null);

  final gw = HttpGateway();

  test('ADS-B.lol Frankfurt çevresinde gerçek uçak döndürür ve konumlar çember içinde', () async {
    const center = LatLng(50.03, 8.57);
    // Açık API zaman zaman yoğun olabilir: uygulamadaki gibi geri çekilerek
    // en fazla 4 deneme.
    List<Aircraft> list = const [];
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        list = await AdsbLolSource(gw).fetchCircle(center, 150);
        // ignore: avoid_print
        print('AIRTRACE_METRIC adsb_attempts=$attempt');
        break;
      } on SourceException catch (e) {
        // ignore: avoid_print
        print('AIRTRACE_METRIC adsb_attempt_failed=$attempt:${e.message}');
        if (attempt == 4) rethrow;
        await Future<void>.delayed(Duration(seconds: 5 * attempt));
      }
    }
    // ignore: avoid_print
    print('AIRTRACE_METRIC adsb_frankfurt_count=${list.length}');
    expect(list, isNotEmpty);
    for (final a in list) {
      expect(Geo.distanceNm(center, LatLng(a.lat, a.lon)), lessThan(160), reason: a.hex);
      expect(a.hex, matches(RegExp(r'^~?[0-9a-f]{6}$')));
    }
    expect(list.where((a) => a.callsign != null), isNotEmpty);
    expect(list.where((a) => a.trackDeg != null && a.groundSpeedMs != null), isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('OpenSky sınır kutusu sorgusu (anonim) — erişilemezse nedeni raporlanır', () async {
    final os = OpenSkySource(gw);
    try {
      final list = await os.fetchStates(const GeoBox(47, 5, 54, 15));
      // ignore: avoid_print
      print('AIRTRACE_METRIC opensky_box_count=${list.length} remaining=${os.remainingCredits}');
      expect(list, isNotEmpty);
      for (final a in list) {
        expect(a.lat, inInclusiveRange(46.5, 54.5));
        expect(a.lon, inInclusiveRange(4.5, 15.5));
      }
    } on SourceException catch (e) {
      // Bulut (CI) IP'leri OpenSky tarafından sık sık engellenir; uygulama bu
      // durumda ADS-B.lol'a geri düşer. Test bunu kayıt altına alır.
      // ignore: avoid_print
      print('AIRTRACE_METRIC opensky_unavailable=${e.runtimeType}:${e.message}');
      markTestSkipped('OpenSky CI ortamından erişilemedi: ${e.message}');
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
