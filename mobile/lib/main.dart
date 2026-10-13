import 'package:flutter/material.dart';

import 'screens/demo_menu_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const GieokhaejwoApp());
}

class GieokhaejwoApp extends StatelessWidget {
  const GieokhaejwoApp({super.key, this.showSplash = true});

  /// 앱 첫 화면(움직이는 로고)을 먼저 보여 줄지
  final bool showSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '기억해줘',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: showSplash
          ? const SplashScreen(next: DemoMenuScreen())
          : const DemoMenuScreen(),
    );
  }
}
