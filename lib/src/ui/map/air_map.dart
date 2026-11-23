import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_scope.dart';
import '../../data/sources/opensky_source.dart';
import '../../domain/fetch_planner.dart';
import '../../domain/geo.dart';
import 'airport_layer.dart';
import 'plane_sprite.dart';
import 'traffic_layer.dart';

/// Ana dünya haritası: OpenStreetMap altlığı (lacivert tona çevrilmiş; isteğe
/// bağlı CARTO Dark Matter) + havalimanları +
/// canlı trafik katmanı.
class AirMap extends StatefulWidget {
  const AirMap({super.key, required this.controller, required this.sprite, required this.frameClock});

  final MapController controller;
  final PlaneSprite sprite;
  final FrameClock frameClock;

  /// Uygulama açılışında tüm dünya görünür.
  /// Widget testlerinde ağdan altlık indirilmesini kapatmak için.
  static bool tilesEnabled = true;

  static final worldBounds = LatLngBounds(const LatLng(-50, -165), const LatLng(70, 170));

  @override
  State<AirMap> createState() => _AirMapState();
}

class _AirMapState extends State<AirMap> {
  final _hits = HitIndex();
  /// Altlık önbelleği diskte en fazla 200 MB (varsayılan 1 GB yerine).
  static NetworkTileProvider? _provider;
  static NetworkTileProvider get _tileProvider => _provider ??= NetworkTileProvider(
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: 200 * 1024 * 1024),
      );

  /// OpenStreetMap standart altlığını koyu lacivert "kontrol merkezi" tonuna
  /// çeviren renk matrisi: parlaklık ters çevrilir (yazılar açık renge döner)
  /// ve lacivert/elektrik mavisi tona eşlenir.
  ///   v = 255 - (0.30R + 0.59G + 0.11B)
  ///   R' = 0.35v + 6,  G' = 0.55v + 10,  B' = 0.85v + 22
  static const _osmNavy = ColorFilter.matrix(<double>[
    -0.105, -0.2065, -0.0385, 0, 95.25, //
    -0.165, -0.3245, -0.0605, 0, 150.25, //
    -0.255, -0.5015, -0.0935, 0, 238.75, //
    0, 0, 0, 1, 0,
  ]);

  /// CARTO Dark Matter (anahtar girildiyse) için hafif lacivert ton.
  static const _cartoNavy = ColorFilter.matrix(<double>[
    0.78, 0, 0, 0, 1, //
    0, 0.92, 0, 0, 6, //
    0, 0, 1.10, 0, 15, //
    0, 0, 0, 1, 0,
  ]);

  Widget _baseLayer(String? cartoKey) {
    final carto = cartoKey != null && cartoKey.isNotEmpty;
    return ColorFiltered(
      colorFilter: carto ? _cartoNavy : _osmNavy,
      child: TileLayer(
        key: ValueKey(carto),
        urlTemplate: carto
            ? 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key={key}'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        additionalOptions: carto ? {'key': cartoKey} : const {},
        maxNativeZoom: 19,
        userAgentPackageName: 'com.furkanbaykal.airtrace',
        tileProvider: _tileProvider,
        tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 120)),
      ),
    );
  }

  void _onPosition(MapCamera camera) {
    final s = AppScope.of(context);
    s.live.setViewport(viewportOf(camera));
  }

  static MapViewport viewportOf(MapCamera camera) {
    final b = camera.visibleBounds;
    final worldW = camera.getWorldWidthAtZoom();
    final lonWidth = worldW > 0 ? camera.nonRotatedSize.width * 360 / worldW : 360.0;
    final c = camera.center;
    GeoBox? box;
    if (lonWidth < 300) {
      final west = c.longitude - lonWidth / 2, east = c.longitude + lonWidth / 2;
      if (west >= -180 && east <= 180) box = GeoBox(b.south, west, b.north, east);
    }
    final radius = box == null
        ? 10800.0
        : [
            LatLng(b.north, box.west),
            LatLng(b.north, box.east),
            LatLng(b.south, box.west),
            LatLng(b.south, box.east),
          ].map((p) => Geo.distanceNm(c, p)).reduce(math.max);
    return MapViewport(center: c, radiusNm: radius, box: box, zoom: camera.zoom);
  }

  void _onTap(TapPosition pos, LatLng _) {
    final s = AppScope.of(context);
    final rel = pos.relative;
    if (rel == null) return;
    final hit = _hits.query(rel);
    if (hit.hex != null) {
      s.selection.select(hit.hex);
    } else if (hit.cluster != null) {
      final cam = widget.controller.camera;
      widget.controller.move(cam.screenOffsetToLatLng(hit.cluster!), math.min(cam.zoom + 2, 14));
    } else {
      s.selection.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: const LatLng(25, 10),
        initialZoom: 2,
        initialCameraFit: CameraFit.bounds(bounds: AirMap.worldBounds, minZoom: 1),
        minZoom: 1,
        maxZoom: 14,
        backgroundColor: const Color(0xFF0A1220),
        cameraConstraint: const CameraConstraint.containLatitude(),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: _onTap,
        onPositionChanged: (camera, _) => _onPosition(camera),
        onMapReady: () => _onPosition(widget.controller.camera),
      ),
      children: [
        if (AirMap.tilesEnabled)
          ListenableBuilder(
            listenable: s.settings,
            builder: (context, _) => _baseLayer(s.settings.cartoKey),
          ),
        AirportLayer(airports: s.staticData.airports),
        TrafficLayer(sprite: widget.sprite, clock: widget.frameClock, hitIndex: _hits),
        const _Attribution(),
      ],
    );
  }
}

/// Harita sağlayıcısının zorunlu atfı (OSM + CARTO). Dar ekranlarda taşmaz.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
          decoration: BoxDecoration(color: const Color(0xAA0A1220), borderRadius: BorderRadius.circular(4)),
          child: Text(
            AppScope.of(context).settings.cartoKey == null ? '© OpenStreetMap katkıcıları' : '© OpenStreetMap katkıcıları © CARTO',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9AA8BD)),
          ),
        ),
      );
}
