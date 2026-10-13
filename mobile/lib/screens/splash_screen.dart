import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 앱 첫 화면: 연한 바탕에 길이 집 쪽으로 생기고 별이 톡, 아래 "기억해줘".
/// 움직임이 끝나면 [next] 화면으로 넘어가요.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// 로고 움직임(3초) + 잠깐 멈춤
  static const duration = Duration(milliseconds: 3300);

  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.duration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => widget.next,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/splash_logo.webp',
              width: width * 0.43,
              height: width * 0.43,
              semanticLabel: '기억해줘 로고',
            ),
            SizedBox(height: width * 0.06),
            Text(
              '기억해줘',
              style: appText(
                width * 0.089,
                weight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
