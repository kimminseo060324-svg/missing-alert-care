import 'package:flutter/material.dart';

import 'data/api_settings.dart';
import 'push/push_service.dart';
import 'screens/demo_menu_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiSettings.load(); // 저장해 둔 서버 주소
  runApp(GieokhaejwoApp(navigatorKey: PushService.navigatorKey));
  if (!kIsWeb) await PushService.start(); // 웹(GitHub Pages)에서는 푸시를 쓰지 않음
}

class GieokhaejwoApp extends StatelessWidget {
  const GieokhaejwoApp({super.key, this.showSplash = true, this.navigatorKey});

  /// 앱 첫 화면(움직이는 로고)을 먼저 보여 줄지
  final bool showSplash;

  /// 푸시 알림을 눌렀을 때 화면을 열 때 써요.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '다시곁에',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: showSplash
          ? const SplashScreen(next: DemoMenuScreen())
          : const DemoMenuScreen(),
    );
  }
}
