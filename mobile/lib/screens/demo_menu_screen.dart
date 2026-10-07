import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'lock_screen.dart';

/// 시연용 첫 화면. 피그마 화면 01~07로 바로 갈 수 있어요.
/// (푸시 알림이 붙으면 01~03은 진짜 알림으로 바뀌어요.)
class DemoMenuScreen extends StatelessWidget {
  const DemoMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 16, title: const Text('기억해줘 · 시연 메뉴')),
      body: FutureBuilder<List<MissingAlert>>(
        future: AlertRepository.instance.loadAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final searching = all.firstWhere((a) => !a.isFound);
          final found = all.firstWhere(
            (a) => a.isFound,
            orElse: () => all.first,
          );

          final items = <(String, String, VoidCallback)>[
            (
              '01',
              '잠금화면 · 접힌 알림',
              () => _open(context, LockScreen.folded(alert: searching)),
            ),
            (
              '02',
              '잠금화면 · 펼친 알림',
              () => _open(context, LockScreen.expanded(alert: searching)),
            ),
            (
              '03',
              '잠금화면 · 발견 완료',
              () => _open(context, LockScreen.found(alert: found)),
            ),
            ('04', '경보 목록', () => AppRoutes.list(context)),
            ('05', '실종 정보 상세', () => AppRoutes.detail(context, searching)),
            ('06', '목격 제보', () => AppRoutes.report(context, searching)),
            ('07', '발견 완료 상세', () => AppRoutes.detail(context, found)),
          ];

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final (no, name, onTap) = items[i];
              return Material(
                color: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Text(
                    no,
                    style: appText(
                      15,
                      weight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  title: Text(
                    name,
                    style: appText(15, weight: FontWeight.w700),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.gray400,
                  ),
                  onTap: onTap,
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}
