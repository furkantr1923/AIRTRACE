import '../data/favorites_store.dart';
import 'traffic_store.dart';

/// Türkçe duyarlı, aksan/büyük-küçük harf bağımsız arama anahtarı.
/// "İstanbul", "ISTANBUL", "istanbul" ve "ıstanbul" aynı anahtara iner.
String foldTr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(switch (c) {
      'İ' || 'I' || 'ı' || 'i' => 'i',
      'Ş' || 'ş' => 's',
      'Ğ' || 'ğ' => 'g',
      'Ü' || 'ü' => 'u',
      'Ö' || 'ö' => 'o',
      'Ç' || 'ç' => 'c',
      'Â' || 'â' => 'a',
      'Î' || 'î' => 'i',
      'Û' || 'û' => 'u',
      _ => c.toLowerCase(),
    });
  }
  return b.toString();
}

class SearchResult {
  const SearchResult({this.track, this.favorite, required this.matchedField});
  final Track? track;
  final FavoriteAircraft? favorite;
  final String matchedField;

  String get hex => track?.hex ?? favorite!.hex;
  bool get isLive => track != null;
}

/// Önce yerel (bellekteki) canlı veride arar; hiçbir ağ isteği atmaz.
/// Uçuş kodu, havayolu, ülke, tescil, tip ve hex alanlarını destekler.
List<SearchResult> searchLocal(
  String query,
  Iterable<Track> tracks,
  Iterable<FavoriteAircraft> favorites, {
  int limit = 60,
}) {
  final q = foldTr(query.trim());
  if (q.isEmpty) return const [];

  final exact = <SearchResult>[];
  final prefix = <SearchResult>[];
  final contains = <SearchResult>[];
  final seen = <String>{};

  void consider(String hex, Map<String, String?> fields, SearchResult Function(String) make) {
    if (seen.contains(hex)) return;
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null || v.isEmpty) continue;
      final f = foldTr(v);
      if (f == q) {
        exact.add(make(e.key));
      } else if (f.startsWith(q)) {
        prefix.add(make(e.key));
      } else if (q.length >= 3 && f.contains(q)) {
        contains.add(make(e.key));
      } else {
        continue;
      }
      seen.add(hex);
      return;
    }
  }

  for (final t in tracks) {
    final a = t.aircraft;
    consider(
      t.hex,
      {
        'Uçuş kodu': a.callsign,
        'Tescil': a.registration,
        'Havayolu': t.airlineName,
        'Ülke': t.country,
        'Tip': a.typeCode,
        'ICAO hex': a.hex,
      },
      (f) => SearchResult(track: t, matchedField: f),
    );
  }
  for (final f in favorites) {
    consider(
      f.hex,
      {
        'Uçuş kodu': f.callsign,
        'Tescil': f.registration,
        'Havayolu': f.airline,
        'Ülke': f.country,
        'Tip': f.typeCode,
        'ICAO hex': f.hex,
      },
      (field) => SearchResult(favorite: f, matchedField: field),
    );
  }
  return [...exact, ...prefix, ...contains].take(limit).toList();
}
