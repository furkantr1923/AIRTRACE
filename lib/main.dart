import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/app_scope.dart';
import 'src/ui/map/plane_sprite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final services = await createServices(prefs);
  final sprite = await PlaneSprite.create();
  runApp(AirtraceApp(services: services, sprite: sprite));
}

/// Test ve uygulama aynı kurulumu kullanır.
Future<AppServices> createServices(SharedPreferences prefs) => buildServices(prefs);
