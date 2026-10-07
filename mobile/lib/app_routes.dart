import 'package:flutter/material.dart';

import 'models/missing_alert.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/alert_list_screen.dart';
import 'screens/found_detail_screen.dart';
import 'screens/report_screen.dart';

/// 화면 이동을 한 곳에 모았어요.
class AppRoutes {
  AppRoutes._();

  static Future<void> _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  static Future<void> list(BuildContext context) =>
      _push(context, const AlertListScreen());

  /// 수색 중이면 05 상세, 발견 완료면 07 발견 완료 상세
  static Future<void> detail(BuildContext context, MissingAlert alert) => _push(
        context,
        alert.isFound
            ? FoundDetailScreen(alert: alert)
            : AlertDetailScreen(alert: alert),
      );

  static Future<void> report(BuildContext context, MissingAlert alert) =>
      _push(context, ReportScreen(alert: alert));

  /// 182 전화 연결은 다음 단계에서 붙여요.
  static void call182(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('182 전화 연결은 다음 단계에서 붙일 예정이에요.')),
    );
  }
}
