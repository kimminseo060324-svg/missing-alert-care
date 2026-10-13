import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/load_state_view.dart';
import 'lock_screen.dart';

/// 시연용 첫 화면. 피그마 화면 01~07로 바로 갈 수 있어요.
/// (푸시 알림이 붙으면 01~03은 진짜 알림으로 바뀌어요.)
class DemoMenuScreen extends StatefulWidget {
  const DemoMenuScreen({super.key, this.repository});

  /// 비워 두면 앱 안의 가짜 데이터를 읽어요. (테스트에서 바꿔 끼워요)
  final AlertRepository? repository;

  @override
  State<DemoMenuScreen> createState() => _DemoMenuScreenState();
}

class _DemoMenuScreenState extends State<DemoMenuScreen> {
  AlertRepository get _repo => widget.repository ?? AlertRepository.instance;
  late Future<List<MissingAlert>> _future = _repo.loadAll();

  void _retry() {
    setState(() {
      _future = _repo.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 16, title: const Text('기억해줘 · 시연 메뉴')),
      body: FutureBuilder<List<MissingAlert>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return LoadErrorView(onRetry: _retry);
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          // 목록이 비었거나 한쪽 상태만 있을 수 있어서 firstWhere 대신 찾기만 해요.
          final searching = all.where((a) => !a.isFound).firstOrNull;
          final found = all.where((a) => a.isFound).firstOrNull;

          final notice = all.isEmpty
              ? const EmptyNotice(
                  title: '지금 표시할 경보가 없어요',
                  sub: '경보가 들어오면 여기에서 바로 볼 수 있어요.',
                )
              : searching == null
              ? const EmptyNotice(
                  title: '지금 수색 중인 경보가 없어요',
                  sub: '모든 경보가 발견 완료됐어요.',
                )
              : null;

          // 화면에 필요한 경보가 없으면 그 줄은 눌리지 않게 해요.
          final items = <(String, String, VoidCallback?)>[
            (
              '01',
              '잠금화면 · 접힌 알림',
              _with(searching, (a) => _open(LockScreen.folded(alert: a))),
            ),
            (
              '02',
              '잠금화면 · 펼친 알림',
              _with(searching, (a) => _open(LockScreen.expanded(alert: a))),
            ),
            (
              '03',
              '잠금화면 · 발견 완료',
              _with(found, (a) => _open(LockScreen.found(alert: a))),
            ),
            (
              '04',
              '경보 목록',
              () => AppRoutes.list(context, repository: widget.repository),
            ),
            (
              '05',
              '실종 정보 상세',
              _with(searching, (a) => AppRoutes.detail(context, a)),
            ),
            (
              '06',
              '목격 제보',
              _with(searching, (a) => AppRoutes.report(context, a)),
            ),
            (
              '07',
              '발견 완료 상세',
              _with(found, (a) => AppRoutes.detail(context, a)),
            ),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (notice != null) ...[notice, const SizedBox(height: 12)],
              for (final (no, name, onTap) in items) ...[
                _MenuTile(no: no, name: name, onTap: onTap),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  VoidCallback? _with(MissingAlert? alert, void Function(MissingAlert) go) =>
      alert == null ? null : () => go(alert);

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.no, required this.name, this.onTap});

  final String no;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Text(
          no,
          style: appText(
            15,
            weight: FontWeight.w800,
            color: on ? AppColors.navy : AppColors.gray400,
          ),
        ),
        title: Text(
          name,
          style: appText(
            15,
            weight: FontWeight.w700,
            color: on ? AppColors.ink : AppColors.gray400,
          ),
        ),
        subtitle: on
            ? null
            : Text('보여줄 경보가 없어요', style: appText(12, color: AppColors.gray400)),
        trailing: on
            ? const Icon(Icons.chevron_right, color: AppColors.gray400)
            : null,
        onTap: onTap,
      ),
    );
  }
}
