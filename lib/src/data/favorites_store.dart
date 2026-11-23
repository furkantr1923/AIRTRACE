import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/aircraft.dart';

/// Favori uçak kaydı. Uçak canlı veriden kaybolsa bile saklanır.
@immutable
class FavoriteAircraft {
  const FavoriteAircraft({
    required this.hex,
    required this.addedAt,
    this.callsign,
    this.registration,
    this.typeCode,
    this.country,
    this.airline,
    this.lastSeenAt,
  });

  final String hex;
  final String? callsign;
  final String? registration;
  final String? typeCode;
  final String? country;
  final String? airline;
  final DateTime addedAt;
  final DateTime? lastSeenAt;

  String get displayName => callsign ?? registration ?? hex.toUpperCase();

  Map<String, Object?> toJson() => {
        'hex': hex,
        'cs': callsign,
        'r': registration,
        't': typeCode,
        'c': country,
        'al': airline,
        'added': addedAt.millisecondsSinceEpoch,
        'seen': lastSeenAt?.millisecondsSinceEpoch,
      };

  static FavoriteAircraft? fromJson(Object? j) {
    if (j is! Map<String, dynamic> || j['hex'] is! String) return null;
    DateTime? t(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return FavoriteAircraft(
      hex: j['hex'] as String,
      callsign: j['cs'] as String?,
      registration: j['r'] as String?,
      typeCode: j['t'] as String?,
      country: j['c'] as String?,
      airline: j['al'] as String?,
      addedAt: t(j['added']) ?? DateTime.now(),
      lastSeenAt: t(j['seen']),
    );
  }

  FavoriteAircraft updatedFrom(Aircraft a, {String? country, String? airline}) => FavoriteAircraft(
        hex: hex,
        addedAt: addedAt,
        callsign: a.callsign ?? callsign,
        registration: a.registration ?? registration,
        typeCode: a.typeCode ?? typeCode,
        country: country ?? this.country,
        airline: airline ?? this.airline,
        lastSeenAt: DateTime.now(),
      );
}

/// Favoriler cihazda yerel olarak (SharedPreferences) saklanır.
/// Hesap veya bulut senkronizasyonu yoktur; Windows ve Android bağımsızdır.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore(this._prefs) {
    _load();
  }

  static const _key = 'airtrace.favorites.v1';
  final SharedPreferences _prefs;
  final Map<String, FavoriteAircraft> _items = {};

  List<FavoriteAircraft> get items =>
      _items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  bool contains(String hex) => _items.containsKey(hex);

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      for (final j in jsonDecode(raw) as List<dynamic>) {
        final f = FavoriteAircraft.fromJson(j);
        if (f != null) _items[f.hex] = f;
      }
    } on FormatException {
      // Bozuk kayıt: sessizce yok say, kullanıcı verisini silme.
    }
  }

  Future<void> _save() => _prefs.setString(_key, jsonEncode([for (final f in _items.values) f.toJson()]));

  Future<void> toggle(Aircraft a, {String? country, String? airline}) async {
    if (_items.remove(a.hex) == null) {
      _items[a.hex] = FavoriteAircraft(hex: a.hex, addedAt: DateTime.now())
          .updatedFrom(a, country: country, airline: airline);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String hex) async {
    if (_items.remove(hex) != null) {
      notifyListeners();
      await _save();
    }
  }

  /// Canlı veride görülen favorilerin kimlik bilgilerini günceller.
  /// Diske yazma sık yapılmaz (en fazla dakikada bir).
  DateTime _lastSeenSave = DateTime.fromMillisecondsSinceEpoch(0);
  void touchSeen(Iterable<Aircraft> live, String? Function(Aircraft) country, String? Function(Aircraft) airline) {
    if (_items.isEmpty) return;
    var changed = false;
    for (final a in live) {
      final f = _items[a.hex];
      if (f != null) {
        _items[a.hex] = f.updatedFrom(a, country: country(a), airline: airline(a));
        changed = true;
      }
    }
    if (changed && DateTime.now().difference(_lastSeenSave) > const Duration(minutes: 1)) {
      _lastSeenSave = DateTime.now();
      unawaited(_save());
    }
  }
}
