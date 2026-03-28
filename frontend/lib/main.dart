// lib/main.dart
// Entry point of the Flutter application.
// Keeps this file minimal - all setup lives in app.dart.

import 'package:flutter/material.dart';
import 'core/notification_service.dart';
import 'app.dart';

Future<void> main() async {
  // Ensures Flutter engine is initialized before any native calls are made.
  // Required when using packages like flutter_secure_storage or local_auth
  // that interact with native platform code before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local budget alert notifications before the app renders.
  await NotificationService.instance.init();

  runApp(const App());
}