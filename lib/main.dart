import 'package:flutter/widget_previews.dart';
import 'package:flutter/material.dart';
import 'screens/main/main_screen.dart';
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