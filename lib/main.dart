import 'package:flutter/material.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  // 1. Required for async code in main
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Check if user was logged in previously
  await AuthService.checkLoginStatus();

  // 3. Start App
  runApp(const VortaxLabsApp());
}

class VortaxLabsApp extends StatelessWidget {
  const VortaxLabsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vortex Labs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: AuthService.isLoggedIn
          ? const MainScreen()
          : const _LoginWrapper(),
    );
  }
}

/// Wrapper to provide onLoginSuccess callback to LoginScreen
class _LoginWrapper extends StatelessWidget {
  const _LoginWrapper();

  @override
  Widget build(BuildContext context) {
    return LoginScreen(
      onLoginSuccess: () {
        // Replace entire stack with fresh MainScreen after login
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      },
    );
  }
}