import 'package:flutter/material.dart';

import 'screens/demo_menu_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const GieokhaejwoApp());
}

class GieokhaejwoApp extends StatelessWidget {
  const GieokhaejwoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '기억해줘',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const DemoMenuScreen(),
    );
  }
}
