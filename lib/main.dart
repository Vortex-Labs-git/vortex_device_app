import 'dart:async';

import 'package:flutter/widget_previews.dart';
import 'package:flutter/material.dart';

import 'controllers/device_repository.dart';
import 'controllers/esp_session.dart';
import 'controllers/network_watcher.dart';
import 'screens/main/main_screen.dart';
import 'services/auth_service.dart';
import 'theme/glass_theme.dart';

void main() async {
  // 1. Required for async code in main
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Check if user was logged in previously
  await AuthService.checkLoginStatus();

  // 3. Start the app-lifetime controllers.
  //    ORDER MATTERS: EspSession and DeviceRepository must be listening
  //    before NetworkWatcher's first emission, or an app launched while
  //    already on a Vortex AP would miss its connect trigger.
  //    (Each start() is idempotent, and both downstream controllers also
  //    seed from .current as a belt-and-braces measure.)
  EspSession.instance.start();
  unawaited(DeviceRepository.instance.start()); // async cache load — don't
  //                                               block the first frame
  NetworkWatcher.instance.start();

  // 4. Start App
  runApp(const VortaxLabsApp());
}

class VortaxLabsApp extends StatelessWidget {
  const VortaxLabsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vortex Labs',
      debugShowCheckedModeBanner: false,
      // Frosted-glass look. Tokens and the ThemeData live in
      // theme/glass_theme.dart; the panes themselves are in widgets/glass/.
      theme: GlassTokens.themeData(),
      home: const MainScreen(),
    );
  }
}

@Preview(
  name: 'Vortax Labs App',
  size: Size(390, 844),
)
Widget vortaxLabsAppPreview() {
  return const VortaxLabsApp();
}
