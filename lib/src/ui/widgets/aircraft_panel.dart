import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/favorites_store.dart';
import '../../data/sources/source_errors.dart';
import '../../domain/geo.dart';
import '../../domain/search.dart';
import '../../domain/sorting.dart';
import '../../domain/traffic_store.dart';

/// Uçak listesi + arama + favoriler. Masaüstünde sol panel, Android'de alt
/// sayfa içinde kullanılır. Liste en fazla saniyede bir yenilenir.
class AircraftPanel extends StatefulWidget {
  const AircraftPanel({super.key, this.scrollController, this.onPicked, this.header});

  final ScrollController? scrollController;

  /// Bir uçak seçildiğinde (mobilde alt sayfayı küçültmek için).
  final VoidCallback? onPicked;
  final Widget? header;

  @override
  State<AircraftPanel> createState() => _AircraftPanelState();
}

enum _Tab { live, favorites }

class _AircraftPanelState extends State<AircraftPanel> {
  final _query = TextEditingController();
  Timer? _refresh;
  int _seenVersion = -1;
  _Tab _tab = _Tab.live;
  List<Track> _rows = const [];
  List<SearchResult> _results = const [];
  bool _remoteBusy = false;
  String? _remoteMessage;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) => _rebuildIfChanged());
    _query.addListener(() => setState(() {
          _remoteMessage = null;
          _recompute();
        }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recompute();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _rebuildIfChanged() {
    if (!mounted) return;
    final s = AppScope.of(context);
    final key = s.store.version ^ (s.live.viewport?.center.hashCode ?? 0);
    if (key == _seenVersion) return;
    _seenVersion = key;
    setState(_recompute);
  }

  void _recompute() {
    final s = AppScope.of(context);
    final q = _query.text.trim();
    if (q.isNotEmpty) {
      _results = searchLocal(q, s.store.tracks, s.favorites.items);
      return;
    }
    final box = s.live.viewport?.box;
    final inView = box == null
        ? s.store.tracks.toList()
        : s.store.tracks
            .where((t) =>
                t.aircraft.lat >= box.south &&
                t.aircraft.lat <= box.north &&
                t.aircraft.lon >= box.west &&
                t.aircraft.lon <= box.east)
            .toList();
    final LatLng? ref = s.location.lastKnown ?? s.live.viewport?.center;
    _rows = sortTracks(inView, s.settings.sortMode, reference: ref);
  }

  void _pick(String hex) {
    AppScope.of(context).selection.select(hex, focus: true);
    widget.onPicked?.call();
  }

  Future<void> _searchRemote() async {
    final s = AppScope.of(context);
    setState(() {
      _remoteBusy = true;
      _remoteMessage = null;
    });
    try {
      final found = await s.live.searchRemote(_query.text);
      if (!mounted) return;
      if (found.isEmpty) {
        _remoteMessage = 'ADS-B.lol üzerinde şu an yayın yapan eşleşme bulunamadı.';
      } else {
        _pick(found.first.hex);
      }
    } on SourceException catch (e) {
      _remoteMessage = 'Ağ araması başarısız: ${e.message}';
    } finally {
      if (mounted) {
        setState(() {
          _remoteBusy = false;
          _recompute();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final favCount = s.favorites.items.length;
    return ListenableBuilder(
      listenable: Listenable.merge([s.favorites, s.selection, s.settings]),
      builder: (context, _) => CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.header != null) widget.header!,
                TextField(
                  key: const Key('search-field'),
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Uçuş kodu, havayolu, ülke, tescil…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Temizle',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _query.clear,
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_query.text.isEmpty)
                  Row(children: [
                    Expanded(
                      child: SegmentedButton<_Tab>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: [
                          ButtonSegment(value: _Tab.live, label: Text('Canlı (${Fmt.count(_rows.length)})')),
                          ButtonSegment(value: _Tab.favorites, label: Text('Favoriler ($favCount)')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (v) => setState(() => _tab = v.first),
                      ),
                    ),
                  ]),
                if (_query.text.isEmpty && _tab == _Tab.live) _sortRow(s),
              ]),
            ),
          ),
          ..._body(s),
        ],
      ),
    );
  }

  Widget _sortRow(AppServices s) {
    final mode = s.settings.sortMode;
    final hasLoc = s.location.lastKnown != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(Icons.sort, size: 16, color: AppColors.textLo),
        const SizedBox(width: 6),
        DropdownButton<SortMode>(
          value: mode,
          isDense: true,
          underline: const SizedBox.shrink(),
          dropdownColor: AppColors.panelHigh,
          style: const TextStyle(fontSize: 13, color: AppColors.textHi),
          items: [for (final m in SortMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
          onChanged: (m) {
            if (m == null) return;
            s.settings.sortMode = m;
            setState(_recompute);
          },
        ),
        const Spacer(),
        if (mode == SortMode.nearest)
          Flexible(
            child: hasLoc
                ? const Text('Konumunuza göre', style: TextStyle(fontSize: 11.5, color: AppColors.textLo))
                : TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                    onPressed: () async {
                      await s.location.locate();
                      if (mounted) setState(_recompute);
                    },
                    child: const Text('Harita merkezine göre · Konumu kullan', style: TextStyle(fontSize: 11.5)),
                  ),
          ),
      ]),
    );
  }

  List<Widget> _body(AppServices s) {
    if (_query.text.trim().isNotEmpty) return _searchBody(s);
    if (_tab == _Tab.favorites) return _favoritesBody(s);
    if (_rows.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Empty(
            text: s.store.isEmpty
                ? 'Henüz uçak verisi yok. Bağlantı durumu üstte gösteriliyor.'
                : 'Görünen alanda uçak yok. Haritayı kaydırın veya uzaklaştırın.',
          ),
        ),
      ];
    }
    final ref = s.location.lastKnown ?? s.live.viewport?.center;
    final showDist = s.settings.sortMode == SortMode.nearest && ref != null;
    return [
      SliverFixedExtentList(
        itemExtent: 58,
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final t = _rows[i];
            return _TrackRow(
              key: ValueKey('track-${t.hex}'),
              track: t,
              selected: t.hex == s.selection.selectedHex,
              favorite: s.favorites.contains(t.hex),
              trailing: showDist ? Fmt.distanceKm(Geo.distanceM(ref, t.lastPosition)) : null,
              onTap: () => _pick(t.hex),
            );
          },
          childCount: _rows.length,
        ),
      ),
    ];
  }

  List<Widget> _searchBody(AppServices s) {
    final q = _query.text.trim();
    return [
      if (_results.isNotEmpty)
        SliverFixedExtentList(
          itemExtent: 58,
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final r = _results[i];
              if (r.track != null) {
                return _TrackRow(
                  track: r.track!,
                  selected: r.hex == s.selection.selectedHex,
                  favorite: s.favorites.contains(r.hex),
                  trailing: r.matchedField,
                  onTap: () => _pick(r.hex),
                );
              }
              return _FavoriteRow(fav: r.favorite!, live: false, onTap: () => _openFavorite(r.favorite!));
            },
            childCount: _results.length,
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_results.isEmpty) const Text('Yüklü canlı veride eşleşme yok.', style: TextStyle(color: AppColors.textMid)),
            if (q.length >= 3) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('remote-search'),
                onPressed: _remoteBusy ? null : _searchRemote,
                icon: _remoteBusy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore, size: 18),
                label: const Text('Tüm dünyada ara (ADS-B.lol)'),
              ),
            ],
            if (_remoteMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_remoteMessage!, style: const TextStyle(color: AppColors.textMid, fontSize: 12.5)),
              ),
          ]),
        ),
      ),
    ];
  }

  List<Widget> _favoritesBody(AppServices s) {
    final favs = s.favorites.items;
    if (favs.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: _Empty(text: 'Henüz favori yok. Bir uçak seçip ☆ simgesine dokunun.'),
        ),
      ];
    }
    return [
      SliverFixedExtentList(
        itemExtent: 58,
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final f = favs[i];
            return _FavoriteRow(fav: f, live: s.store[f.hex] != null, onTap: () => _openFavorite(f));
          },
          childCount: favs.length,
        ),
      ),
    ];
  }

  Future<void> _openFavorite(FavoriteAircraft f) async {
    final s = AppScope.of(context);
    if (s.store[f.hex] != null) {
      _pick(f.hex);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final found = await s.live.searchRemote(f.hex);
      if (!mounted) return;
      if (found.isNotEmpty) {
        _pick(f.hex);
      } else {
        messenger.showSnackBar(SnackBar(content: Text('${f.displayName} şu an canlı veride görünmüyor.')));
      }
    } on SourceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sorgulanamadı: ${e.message}')));
    }
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({super.key, required this.track, required this.selected, required this.favorite, required this.onTap, this.trailing});
  final Track track;
  final bool selected;
  final bool favorite;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = track.aircraft;
    final sub = [
      track.airlineName ?? a.typeCode,
      track.country,
    ].whereType<String>().join(' · ');
    return Material(
      color: selected ? AppColors.electric.withValues(alpha: 0.14) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Transform.rotate(
              angle: (a.trackDeg ?? 0) * 3.1415926535 / 180,
              child: Icon(Icons.flight,
                  size: 18, color: favorite ? AppColors.gold : (a.onGround ? AppColors.ground : AppColors.electric)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.3)),
                Text(sub.isEmpty ? Fmt.unknown : sub,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textMid)),
              ]),
            ),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fmt.altitude(a.altitudeM, onGround: a.onGround), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(trailing ?? Fmt.speed(a.groundSpeedMs), style: const TextStyle(fontSize: 11, color: AppColors.textLo)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({required this.fav, required this.live, required this.onTap});
  final FavoriteAircraft fav;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sub = [fav.airline ?? fav.typeCode, fav.country].whereType<String>().join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(children: [
          const Icon(Icons.star_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fav.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text(
                [if (sub.isNotEmpty) sub, live ? 'Canlı' : (fav.lastSeenAt != null ? 'Son görülme ${Fmt.ago(DateTime.now().difference(fav.lastSeenAt!))}' : 'Görünmüyor')]
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: live ? AppColors.ok : AppColors.textMid),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Favorilerden çıkar',
            icon: const Icon(Icons.delete_outline, size: 19),
            onPressed: () => s.favorites.remove(fav.hex),
          ),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMid, fontSize: 13)),
      );
}
