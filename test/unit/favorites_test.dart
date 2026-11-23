import 'package:airtrace/src/data/favorites_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

void main() {
  test('favoriler kalıcıdır ve uçak kaybolsa da silinmez', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FavoritesStore(prefs);
    await store.toggle(testAircraft(), country: 'Türkiye', airline: 'Turkish Airlines');
    expect(store.contains('4bb1a1'), isTrue);

    // "Uygulamayı yeniden aç": aynı kalıcı depodan yeni örnek.
    final reopened = FavoritesStore(prefs);
    final f = reopened.items.single;
    expect(f.callsign, 'THY4KJ');
    expect(f.country, 'Türkiye');
    expect(f.airline, 'Turkish Airlines');

    await reopened.toggle(testAircraft());
    expect(FavoritesStore(prefs).items, isEmpty);
  });

  test('bozuk kayıt uygulamayı çökertmez', () async {
    SharedPreferences.setMockInitialValues({'airtrace.favorites.v1': '{bozuk'});
    final prefs = await SharedPreferences.getInstance();
    expect(FavoritesStore(prefs).items, isEmpty);
  });
}
