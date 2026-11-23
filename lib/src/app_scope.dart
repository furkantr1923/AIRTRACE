import 'package:flutter/widgets.dart';

import 'data/favorites_store.dart';
import 'data/location_service.dart';
import 'data/route_service.dart';
import 'data/settings_store.dart';
import 'data/sources/http_gateway.dart';
import 'data/static_data.dart';
import 'domain/live_traffic_controller.dart';
import 'domain/selection_controller.dart';
import 'domain/traffic_store.dart';

/// Uygulama servislerini widget ağacına taşır. Harici durum yönetimi paketi
/// kullanılmaz; ChangeNotifier + ListenableBuilder yeterlidir.
class AppServices {
  AppServices({
    required this.http,
    required this.staticData,
    required this.store,
    required this.live,
    required this.favorites,
    required this.settings,
    required this.location,
    required this.routes,
    required this.selection,
  });

  final HttpGateway http;
  final StaticData staticData;
  final TrafficStore store;
  final LiveTrafficController live;
  final FavoritesStore favorites;
  final SettingsStore settings;
  final LocationService location;
  final RouteService routes;
  final SelectionController selection;

  /// Ayarlar'da OpenSky bilgileri değişince kaynağa uygular.
  void openSkyCredentialsChanged() =>
      live.openSky.setCredentials(settings.openSkyClientId, settings.openSkyClientSecret);
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
