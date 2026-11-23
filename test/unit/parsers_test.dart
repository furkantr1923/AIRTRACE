import 'package:airtrace/src/data/models/aircraft.dart';
import 'package:airtrace/src/data/route_service.dart';
import 'package:airtrace/src/data/sources/adsblol_source.dart';
import 'package:airtrace/src/data/sources/opensky_source.dart';
import 'package:airtrace/src/data/sources/source_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ADS-B.lol ayrıştırıcı', () {
    final body = {
      'now': 1767268800000,
      'ac': [
        {
          'hex': '4BB1A1', 'flight': 'THY4KJ  ', 'r': 'TC-JJA', 't': 'B77W',
          'alt_baro': 35000, 'gs': 480.0, 'track': 92.5, 'baro_rate': -640,
          'lat': 41.25, 'lon': 28.75, 'seen_pos': 2.0, 'squawk': '2341',
        },
        {'hex': '4bb1a2', 'alt_baro': 'ground', 'gs': 3, 'lat': 41.27, 'lon': 28.74, 'seen_pos': 0.5},
        {'hex': '4bb1a3', 'alt_baro': 12000}, // konumsuz -> atlanır
        {'hex': '4bb1a4', 'lat': 40, 'lon': 29, 'seen_pos': 120}, // eski -> atlanır
      ],
    };

    test('birimleri SI\'ya çevirir ve konum zamanını hesaplar', () {
      final list = AdsbLolSource.parse(body);
      expect(list, hasLength(2));
      final a = list.first;
      expect(a.hex, '4bb1a1');
      expect(a.callsign, 'THY4KJ');
      expect(a.registration, 'TC-JJA');
      expect(a.altitudeM, closeTo(10668, 1));
      expect(a.groundSpeedMs, closeTo(246.9, 0.2));
      expect(a.verticalRateMs, closeTo(-3.25, 0.01));
      expect(a.trackDeg, 92.5);
      expect(a.positionTime, DateTime.fromMillisecondsSinceEpoch(1767268798000, isUtc: true));
      expect(a.source, DataSource.adsbLol);
      expect(a.airlineIcao, 'THY');
    });

    test('yerdeki uçak: irtifa uydurulmaz', () {
      final g = AdsbLolSource.parse(body)[1];
      expect(g.onGround, isTrue);
      expect(g.altitudeM, isNull);
      expect(g.callsign, isNull);
      expect(g.displayName, '4BB1A2');
    });

    test('geçersiz yanıt hata verir', () {
      expect(() => AdsbLolSource.parse('x'), throwsA(isA<ProviderException>()));
    });
  });

  group('OpenSky ayrıştırıcı', () {
    test('state vector alan sırası doğru okunur', () {
      final list = OpenSkySource.parse({
        'time': 1767268800,
        'states': [
          ['4bb1a1', 'THY4KJ  ', 'Turkey', 1767268795, 1767268799, 28.75, 41.25, 10668.0, false, 246.9, 92.5, -3.2, null, 10900.0, '2341', false, 0],
          ['abc123', null, 'United States', null, 1767268799, -70.0, 40.0, 1000.0, false, 100.0, 10.0, 0.0, null, null, null, false, 0],
        ],
      });
      expect(list, hasLength(1));
      final a = list.single;
      expect(a.lat, 41.25);
      expect(a.lon, 28.75);
      expect(a.altitudeM, 10668.0);
      expect(a.originCountry, 'Turkey');
      expect(a.source, DataSource.openSky);
    });

    test('kredi maliyeti alana göre', () {
      expect(OpenSkySource.creditCost(null), 4);
      expect(OpenSkySource.creditCost(const GeoBox(40, 28, 44, 32)), 1);
      expect(OpenSkySource.creditCost(const GeoBox(40, 20, 48, 30)), 2);
      expect(OpenSkySource.creditCost(const GeoBox(30, 0, 50, 20)), 3);
      expect(OpenSkySource.creditCost(const GeoBox(0, 0, 50, 50)), 4);
    });
  });

  group('Rota servisi', () {
    test('yalnızca plausible=true rotalar kabul edilir', () {
      final airports = [
        {'iata': 'IST', 'icao': 'LTFM', 'name': 'Istanbul', 'lat': 41.27, 'lon': 28.75},
        {'iata': 'LHR', 'icao': 'EGLL', 'name': 'Heathrow', 'lat': 51.47, 'lon': -0.45},
      ];
      expect(RouteService.parse([{'plausible': true, '_airports': airports}])!.origin.code, 'IST');
      expect(RouteService.parse([{'plausible': false, '_airports': airports}]), isNull);
      expect(RouteService.parse([{'_airports': <Object>[]}]), isNull);
    });
  });
}
