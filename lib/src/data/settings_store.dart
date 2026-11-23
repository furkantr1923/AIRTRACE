import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sorting.dart';

/// Kullanıcı tercihleri (yalnızca cihazda saklanır).
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  static const _kSort = 'airtrace.sort';
  static const _kOsId = 'airtrace.opensky.id';
  static const _kOsSecret = 'airtrace.opensky.secret';
  static const _kCarto = 'airtrace.carto.key';

  final SharedPreferences _prefs;

  SortMode get sortMode =>
      SortMode.values.firstWhere((m) => m.name == _prefs.getString(_kSort), orElse: () => SortMode.nearest);

  set sortMode(SortMode m) {
    _prefs.setString(_kSort, m.name);
    notifyListeners();
  }

  /// İsteğe bağlı OpenSky istemci bilgileri. Kaynak koduna gömülmez,
  /// loglanmaz; yalnızca bu cihazın uygulama verisinde tutulur.
  String? get openSkyClientId => _prefs.getString(_kOsId);
  String? get openSkyClientSecret => _prefs.getString(_kOsSecret);

  Future<void> setOpenSkyCredentials(String? id, String? secret) async {
    if (id == null || id.trim().isEmpty || secret == null || secret.trim().isEmpty) {
      await _prefs.remove(_kOsId);
      await _prefs.remove(_kOsSecret);
    } else {
      await _prefs.setString(_kOsId, id.trim());
      await _prefs.setString(_kOsSecret, secret.trim());
    }
    notifyListeners();
  }

  /// İsteğe bağlı ücretsiz CARTO anahtarı (carto.com/basemaps/apikey).
  /// Girilirse "Dark Matter" altlığı kullanılır; yoksa OpenStreetMap.
  String? get cartoKey => _prefs.getString(_kCarto);

  Future<void> setCartoKey(String? key) async {
    final k = key?.trim();
    if (k == null || k.isEmpty) {
      await _prefs.remove(_kCarto);
    } else {
      await _prefs.setString(_kCarto, k);
    }
    notifyListeners();
  }
}
