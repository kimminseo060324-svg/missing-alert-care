import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/hero_header.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/timeline.dart';
import 'alert_list_screen.dart';

/// 07 발견 완료 상세
/// 발견되면 사진(그림)과 상세 정보는 개인정보 보호를 위해 보여주지 않아요.
class FoundDetailScreen extends StatelessWidget {
  const FoundDetailScreen({super.key, required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실종경보 상세')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          HeroHeader(
            found: true,
            label: '실종경보 종료 · ${alert.region}',
            chip: StatusChip.found(alert.foundTime, tone: ChipTone.onColor),
            title: alert.ageSex,
            meta: '${alert.occrDateText} 발생 · ${alert.foundTime} 종료',
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '✓',
                      style: appText(
                        28,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '안전하게 발견됐어요',
                    style: appText(18, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '사진과 상세 정보는\n개인정보 보호를 위해 삭제했어요.',
                    textAlign: TextAlign.center,
                    style: appText(13, color: AppColors.gray600, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '경보 진행 기록',
            child: Timeline(
              entries: [
                TimelineEntry(alert.occrDateShort, '실종경보 발령'),
                TimelineEntry(alert.foundTime, '발견 완료 · 경보 종료', done: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '관심 가져 주셔서 고마워요.',
            textAlign: TextAlign.center,
            style: appText(13, color: AppColors.gray600),
          ),
          const SizedBox(height: 8),
          const SourceText(center: true),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: AppButton(
          label: '목록으로',
          primary: false,
          large: true,
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AlertListScreen()),
            (route) => route.isFirst,
          ),
        ),
      ),
    );
  }
}
