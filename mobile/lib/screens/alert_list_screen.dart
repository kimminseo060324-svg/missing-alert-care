import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/alert_list_item.dart';
import '../widgets/hero_header.dart';
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
        final searching = all.where((a) => !a.isFound).toList();
        final regions = searching.map((a) => a.region).toSet().take(2);
        final shown = switch (_filter) {
          _Filter.all => all,
          _Filter.searching => searching,
          _Filter.found => all.where((a) => a.isFound).toList(),
        };

        return Scaffold(
          body: Column(
            children: [
              ScreenHeader(
                title: '내 주변 실종경보',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (regions.isNotEmpty) ...[
                      PillAlign(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.place,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                regions.join(' · '),
                                style: appText(
                                  12,
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '수색 중 ',
                            style: appText(
                              13,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          TextSpan(
                            text: '${searching.length}',
                            style: appText(
                              40,
                              weight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: '건',
                            style: appText(
                              16,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          Row(
                            children: [
                              _chip('전체', _Filter.all),
                              const SizedBox(width: 6),
                              _chip('수색 중', _Filter.searching),
                              const SizedBox(width: 6),
                              _chip('발견 완료', _Filter.found),
                            ],
                          ),
                          const SizedBox(height: 14),
                          for (final (i, a) in shown.indexed) ...[
                            AlertListItem(
                              alert: a,
                              number: i + 1,
                              selected: _filter == _Filter.all && i == 0,
                              onTap: () => AppRoutes.detail(context, a),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 4),
                          const SourceText(),
                        ],
                      ),
              ),
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
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: appText(
              13,
              weight: FontWeight.w700,
              color: on ? Colors.white : AppColors.gray600,
            ),
          ),
        ),
      ),
    );
  }
}
