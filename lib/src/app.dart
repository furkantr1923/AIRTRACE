import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'core/theme.dart';
import 'data/favorites_store.dart';
import 'data/location_service.dart';
import 'data/route_service.dart';
import 'data/settings_store.dart';
import 'data/sources/adsblol_source.dart';
import 'data/sources/http_gateway.dart';
import 'data/sources/opensky_source.dart';
import 'data/static_data.dart';
import 'domain/live_traffic_controller.dart';
import 'domain/selection_controller.dart';
import 'domain/traffic_store.dart';
import 'ui/home_page.dart';
import 'ui/map/plane_sprite.dart';

/// Tüm servisleri bağlar. [http] testlerde değiştirilebilir.
Future<AppServices> buildServices(SharedPreferences prefs, {HttpGateway? http}) async {
  final gateway = http ?? HttpGateway();
  final staticData = await StaticData.load();
  final store = TrafficStore(staticData);
  final settings = SettingsStore(prefs);
  final openSky = OpenSkySource(gateway)..setCredentials(settings.openSkyClientId, settings.openSkyClientSecret);
  final live = LiveTrafficController(store: store, adsb: AdsbLolSource(gateway), openSky: openSky);
  final routes = RouteService(gateway);
  final favorites = FavoritesStore(prefs);
  // Canlı görülen favorilerin kimlik bilgileri güncel tutulur.
  store.addListener(() => favorites.touchSeen(
        store.tracks.where((t) => favorites.contains(t.hex)).map((t) => t.aircraft),
        store.countryOf,
        store.airlineOf,
      ));
  return AppServices(
    http: gateway,
    staticData: staticData,
    store: store,
    live: live,
    favorites: favorites,
    settings: settings,
    location: LocationService(),
    routes: routes,
    selection: SelectionController(store: store, live: live, routes: routes),
  );
}

class AirtraceApp extends StatelessWidget {
  const AirtraceApp({super.key, required this.services, required this.sprite, this.repaintKey});

  final AppServices services;
  final PlaneSprite sprite;

  /// Entegrasyon testlerinde ekran görüntüsü almak için.
  final GlobalKey? repaintKey;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: RepaintBoundary(
        key: repaintKey,
        child: MaterialApp(
          title: 'AIRTRACE',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: HomePage(sprite: sprite),
        ),
      ),
    );
  }
}
