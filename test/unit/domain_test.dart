import 'dart:ui';

import 'package:airtrace/src/core/format.dart';
import 'package:airtrace/src/data/sources/opensky_source.dart';
import 'package:airtrace/src/domain/clustering.dart';
import 'package:airtrace/src/domain/fetch_planner.dart';
import 'package:airtrace/src/domain/geo.dart';
import 'package:airtrace/src/domain/interpolation.dart';
import 'package:airtrace/src/domain/search.dart';
import 'package:airtrace/src/domain/sorting.dart';
import 'package:airtrace/src/domain/traffic_store.dart';
import 'package:airtrace/src/ui/map/plane_sprite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/fixtures.dart';

void main() {
  final data = loadStaticData();
  final t0 = DateTime.utc(2026, 1, 1, 12);

  group('Statik veri', () {
    test('ICAO bloğundan Türkçe ülke', () {
      expect(data.countryForHex('4bb1a1'), 'Türkiye');
      expect(data.countryForHex('a12345'), 'Amerika Birleşik Devletleri');
      expect(data.countryForHex('3c6444'), 'Almanya');
      expect(data.countryForHex('~123456'), isNull);
    });
    test('havayolu ve havalimanları', () {
      expect(data.airlineName('THY'), 'Turkish Airlines');
      expect(data.airports.length, greaterThan(1000));
      expect(data.airports.any((a) => a.iata == 'IST'), isTrue);
    });
  });

  group('Geometri ve ara değerleme', () {
    test('mesafe: İstanbul–Ankara ~ 350 km', () {
      expect(Geo.distanceM(const LatLng(41.0, 28.98), const LatLng(39.93, 32.86)) / 1000, closeTo(350, 10));
    });

    test('doğuya giden uçak tahminde doğuya ilerler', () {
      const ip = Interpolator();
      final a = testAircraft(time: t0, speed: 250, track: 90);
      final p = ip.at(a, t0.add(const Duration(seconds: 20)));
      expect(p.isPredicted, isTrue);
      expect(p.isStale, isFalse);
      expect(p.position.longitude, greaterThan(a.lon));
      expect(Geo.distanceM(LatLng(a.lat, a.lon), p.position), closeTo(5000, 30));
    });

    test('tahmin süresi sınırlı; sonrası eski veri olarak işaretlenir', () {
      const ip = Interpolator();
      final a = testAircraft(time: t0, speed: 250, track: 0);
      final p60 = ip.at(a, t0.add(const Duration(seconds: 60)));
      final p300 = ip.at(a, t0.add(const Duration(seconds: 300)));
      expect(p300.isStale, isTrue);
      expect(p300.position.latitude, closeTo(p60.position.latitude, 1e-9));
    });

    test('yerdeki uçak tahmin edilmez', () {
      final p = const Interpolator().at(testAircraft(time: t0, onGround: true), t0.add(const Duration(seconds: 30)));
      expect(p.isPredicted, isFalse);
    });

    test('uçak simgesi yönü: 90° burnu doğuya çevirir', () {
      for (final (deg, dx, dy) in [(0.0, 0.0, -1.0), (90.0, 1.0, 0.0), (180.0, 0.0, 1.0), (270.0, -1.0, 0.0)]) {
        final tf = atlasTransform(const Offset(100, 100), deg, 1);
        // Sprite içindeki burun noktası (32,3) -> ekran
        const nx = 32.0, ny = 3.0;
        final x = tf.scos * nx - tf.ssin * ny + tf.tx;
        final y = tf.ssin * nx + tf.scos * ny + tf.ty;
        expect((x - 100) / 29, closeTo(dx, 1e-6), reason: '$deg°');
        expect((y - 100) / 29, closeTo(dy, 1e-6), reason: '$deg°');
      }
    });
  });

  group('Trafik deposu', () {
    test('eski konum yeni konumu ezmez, kimlik birleştirilir', () {
      final s = TrafficStore(data);
      s.ingest([testAircraft(time: t0)], expectedRefresh: const Duration(seconds: 10), now: t0);
      s.ingest([testAircraft(time: t0.subtract(const Duration(seconds: 5)), lat: 0)], expectedRefresh: const Duration(seconds: 10), now: t0);
      expect(s['4bb1a1']!.aircraft.lat, 41.0);
      s.ingest([testAircraft(time: t0.add(const Duration(seconds: 10)), lat: 41.1, callsign: null)],
          expectedRefresh: const Duration(seconds: 10), now: t0);
      final t = s['4bb1a1']!;
      expect(t.aircraft.callsign, 'THY4KJ');
      expect(t.trail, hasLength(2));
      expect(t.country, 'Türkiye');
      expect(t.airlineName, 'Turkish Airlines');
    });

    test('çevrimiçiyken eski kayıtlar temizlenir, çevrimdışıyken korunur', () {
      final s = TrafficStore(data);
      s.ingest([testAircraft()], expectedRefresh: const Duration(seconds: 10), now: t0);
      final later = t0.add(const Duration(minutes: 5));
      expect(s.prune(online: false, now: later), 0);
      expect(s.length, 1);
      expect(s.prune(online: true, now: later), 1);
      expect(s.isEmpty, isTrue);
    });
  });

  group('Veri planlayıcı ve limitler', () {
    const p = FetchPlanner();
    test('dar görünüm: yalnızca ADS-B.lol', () {
      final plan = p.plan(const Viewport(center: LatLng(41, 29), radiusNm: 120, box: GeoBox(39, 27, 43, 31), zoom: 8),
          openSkyAvailable: true);
      expect(plan.useAdsbLol, isTrue);
      expect(plan.useOpenSky, isFalse);
      expect(plan.circleRadiusNm, lessThanOrEqualTo(250));
    });
    test('dünya görünümü: OpenSky; kota yoksa ADS-B.lol merkez çemberi', () {
      const v = Viewport(center: LatLng(20, 0), radiusNm: 9000, box: null, zoom: 2);
      final a = p.plan(v, openSkyAvailable: true);
      expect(a.useOpenSky, isTrue);
      expect(a.useAdsbLol, isFalse);
      final b = p.plan(v, openSkyAvailable: false);
      expect(b.useOpenSky, isFalse);
      expect(b.circleRadiusNm, 250);
    });
    test('OpenSky bütçesi: anonim dünya sorgusu ≥ 60 sn, kota bitince gece yarısına kadar', () {
      const b = OpenSkyBudget();
      final anon = b.interval(cost: 4, remaining: 400, daily: 400, authenticated: false);
      expect(anon.inSeconds, greaterThanOrEqualTo(60));
      // Saatte kalan kredinin en fazla %25'i: 98 çağrı -> saatte ~24 -> ~147 sn
      expect(anon.inSeconds, closeTo(147, 3));
      final auth = b.interval(cost: 4, remaining: 4000, daily: 4000, authenticated: true);
      expect(auth.inSeconds, 20);
      final none = b.interval(cost: 4, remaining: 9, daily: 400, authenticated: false, nowUtc: DateTime.utc(2026, 1, 1, 22));
      expect(none, const Duration(hours: 2));
    });
  });

  group('Arama, sıralama, kümelendirme, biçim', () {
    TrafficStore store() => TrafficStore(data)
      ..ingest([
        testAircraft(hex: '4bb1a1', callsign: 'THY4KJ', lat: 41, lon: 29, speed: 200, alt: 9000),
        testAircraft(hex: '3c6444', callsign: 'DLH400', lat: 50, lon: 8, speed: 250, alt: 11000),
        testAircraft(hex: 'a12345', callsign: 'N123AB', lat: 40, lon: -74, speed: 60, alt: 1000),
      ], expectedRefresh: const Duration(seconds: 10), now: t0);

    test('Türkçe karakter duyarsız arama: ülke, havayolu, uçuş kodu', () {
      final s = store();
      expect(foldTr('İSTANBUL'), foldTr('istanbul'));
      expect(searchLocal('turkiye', s.tracks, const []).single.hex, '4bb1a1');
      expect(searchLocal('lufthansa', s.tracks, const []).single.hex, '3c6444');
      expect(searchLocal('dlh4', s.tracks, const []).single.matchedField, 'Uçuş kodu');
      expect(searchLocal('', s.tracks, const []), isEmpty);
    });

    test('sıralamalar', () {
      final s = store();
      final near = sortTracks(s.tracks.toList(), SortMode.nearest, reference: const LatLng(41, 28.9));
      expect(near.first.hex, '4bb1a1');
      expect(sortTracks(s.tracks.toList(), SortMode.speed).first.hex, '3c6444');
      expect(sortTracks(s.tracks.toList(), SortMode.altitude).last.hex, 'a12345');
      expect(sortTracks(s.tracks.toList(), SortMode.callsign).first.aircraft.callsign, 'DLH400');
    });

    test('kümelendirme yoğun hücreleri birleştirir', () {
      final pts = [for (var i = 0; i < 10; i++) Offset(10.0 + i, 10), const Offset(500, 500)];
      final r = GridClusterer().run(pts);
      expect(r.clusters.single.count, 10);
      expect(r.singles, [10]);
    });

    test('biçimlendirme uydurmaz', () {
      expect(Fmt.speed(null), 'Bilinmiyor');
      expect(Fmt.altitude(null, onGround: true), 'Yerde');
      expect(Fmt.speed(250), '900 km/sa');
      expect(Fmt.altitude(10668), '10.670 m');
      expect(Fmt.count(12345), '12.345');
    });
  });
}
