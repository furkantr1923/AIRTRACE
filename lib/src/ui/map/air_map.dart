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

/// Ana dünya haritası: CARTO koyu altlık (lacivert tonlu) + havalimanları +
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

  /// Koyu gri CARTO altlığını lacivert/antrasit tonuna çeken renk matrisi.
  static const _navyTint = ColorFilter.matrix(<double>[
    0.78, 0, 0, 0, 1, //
    0, 0.92, 0, 0, 6, //
    0, 0, 1.10, 0, 15, //
    0, 0, 0, 1, 0,
  ]);

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
          ColorFiltered(
            colorFilter: _navyTint,
            child: TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              maxNativeZoom: 19,
              userAgentPackageName: 'com.furkanbaykal.airtrace',
              tileProvider: _tileProvider,
              tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 120)),
            ),
          ),
        AirportLayer(airports: s.staticData.airports),
        TrafficLayer(sprite: widget.sprite, clock: widget.frameClock, hitIndex: _hits),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap katkıcıları  © CARTO', style: TextStyle(fontSize: 10)),
          backgroundColor: Color(0xAA0A1220),
        ),
      ],
    );
  }
}
