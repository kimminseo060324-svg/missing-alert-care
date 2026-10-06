import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/alert_list_item.dart';
import '../widgets/section_card.dart';

enum _Filter { all, searching, found }

/// 04 경보 목록 ("내 주변 실종경보")
/// 경찰청 자료엔 좌표가 없어서 거리 대신 지역명을 보여줘요.
class AlertListScreen extends StatefulWidget {
  const AlertListScreen({super.key});

  @override
  State<AlertListScreen> createState() => _AlertListScreenState();
}

class _AlertListScreenState extends State<AlertListScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MissingAlert>>(
      future: AlertRepository.instance.loadAll(),
      builder: (context, snap) {
        final all = snap.data ?? const <MissingAlert>[];
        final searchingCount = all.where((a) => !a.isFound).length;
        final shown = switch (_filter) {
          _Filter.all => all,
          _Filter.searching => all.where((a) => !a.isFound).toList(),
          _Filter.found => all.where((a) => a.isFound).toList(),
        };

        return Scaffold(
          appBar: AppBar(
            title: const Text('내 주변 실종경보'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '수색 중 $searchingCount건',
                    style: appText(12, color: AppColors.gray600),
                  ),
                ),
              ),
            ],
          ),
          body: !snap.hasData
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Row(
                      children: [
                        _chip('전체', _Filter.all),
                        const SizedBox(width: 8),
                        _chip('수색 중', _Filter.searching),
                        const SizedBox(width: 8),
                        _chip('발견 완료', _Filter.found),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final a in shown) ...[
                      AlertListItem(
                        alert: a,
                        onTap: () => AppRoutes.detail(context, a),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SourceText(),
                  ],
                ),
        );
      },
    );
  }

  Widget _chip(String label, _Filter value) {
    final on = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.gray900 : AppColors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: on ? AppColors.gray900 : AppColors.gray200),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: appText(
              13,
              weight: FontWeight.w700,
              color: on ? Colors.white : AppColors.gray900,
            ),
          ),
        ),
      ),
    );
  }
}
