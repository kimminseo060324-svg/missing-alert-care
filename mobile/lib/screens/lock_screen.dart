import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_routes.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/notification_card.dart';

enum LockMode { folded, expanded, found }

/// 01~03 잠금화면 알림 미리보기.
/// 진짜 푸시 알림이 붙기 전까지 시연용으로 잠금화면을 흉내 내요.
class LockScreen extends StatefulWidget {
  const LockScreen.folded({super.key, required this.alert})
      : mode = LockMode.folded;
  const LockScreen.expanded({super.key, required this.alert})
      : mode = LockMode.expanded;
  const LockScreen.found({super.key, required this.alert})
      : mode = LockMode.found;

  final MissingAlert alert;
  final LockMode mode;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late LockMode _mode = widget.mode;

  @override
  void didUpdateWidget(LockScreen old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _mode = widget.mode;
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final date = '${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}요일';
    final alert = widget.alert;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.lockTop, AppColors.lockBottom],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Text(
                  clock,
                  textAlign: TextAlign.center,
                  style: appText(64, color: Colors.white, height: 1),
                ),
                const SizedBox(height: 8),
                Text(
                  date,
                  textAlign: TextAlign.center,
                  style: appText(14, color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ..._cards(alert),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _cards(MissingAlert alert) {
    switch (_mode) {
      case LockMode.folded:
        return [
          const GeneralNotiCard(
            source: '안전안내문자 · 오산시',
            time: '1시간 전',
            title: '단수 예정 안내',
            body: '10/7(수) 09~15시 ○○동 일대',
          ),
          const SizedBox(height: 8),
          AlertNotiFolded(
            alert: alert,
            onTap: () => setState(() => _mode = LockMode.expanded),
          ),
        ];
      case LockMode.expanded:
        return [
          AlertNotiExpanded(
            alert: alert,
            onDetail: () => AppRoutes.detail(context, alert),
            onReport: () => AppRoutes.report(context, alert),
          ),
        ];
      case LockMode.found:
        return [
          FoundNotiCard(
            alert: alert,
            onTap: () => AppRoutes.detail(context, alert),
          ),
        ];
    }
  }
}
