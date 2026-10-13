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
      body: Column(
        children: [
          ScreenHeader(
            title: '실종경보 상세',
            found: true,
            child: HeroInfo(
              chip: StatusChip.found(alert.foundTime, tone: ChipTone.onColor),
              title: alert.ageSex,
              meta:
                  '${alert.region}  ·  ${alert.occrDateText} 발령  ·  ${alert.foundTime} 종료',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '안전하게 발견됐어요',
                              style: appText(20, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '사진과 상세 정보는\n개인정보 보호를 위해 삭제했어요.',
                              textAlign: TextAlign.center,
                              style: appText(
                                13,
                                color: AppColors.gray600,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '진행 기록',
                    child: Timeline(
                      entries: [
                        TimelineEntry(alert.occrDateShort, '실종경보 발령'),
                        TimelineEntry(
                          alert.foundTime,
                          '발견 완료 · 경보 종료',
                          done: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '관심 가져 주셔서 고마워요.',
                    textAlign: TextAlign.center,
                    style: appText(12, color: AppColors.gray400),
                  ),
                  const SizedBox(height: 8),
                  const SourceText(center: true),
                ],
              ),
            ),
          ),
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
