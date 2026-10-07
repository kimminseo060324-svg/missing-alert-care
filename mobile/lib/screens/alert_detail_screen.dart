import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/hero_header.dart';
import '../widgets/outfit_figure.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/swatch_tile.dart';
import '../widgets/timeline.dart';

/// 05 실종 정보 상세 (수색 중)
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            title: '실종경보 상세',
            child: HeroInfo(
              chip: const StatusChip.searching(tone: ChipTone.onColor),
              title: '${alert.maskedName} 씨',
              sub: '${alert.sexLong} · ${alert.age}세',
              meta: '${alert.region}  ·  ${alert.occrDateText} 발령',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 이것만 기억하세요: 핵심 3가지를 색 칸으로
                  SectionCard(
                    title: '이것만 기억하세요',
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SwatchTile(label: '상의', text: alert.topText),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SwatchTile(
                              label: '하의·신발',
                              text: alert.bottomText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child:
                                SwatchTile(label: '키', text: alert.heightText),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 인상착의: 옷차림 그림 + 2칸 정보
                  SectionCard(
                    title: '인상착의',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutfitPanel(alert: alert),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InfoTile(
                                label: '키',
                                value: alert.heightText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child:
                                  InfoTile(label: '체형', value: alert.bodyText),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child:
                                  InfoTile(label: '상의', value: alert.topText),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InfoTile(
                                label: '하의·신발',
                                value: alert.bottomText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '그림은 AI가 문자 내용으로 그린 옷차림이에요. 얼굴은 그리지 않아요.',
                          style: appText(
                            11,
                            color: AppColors.gray400,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 마지막 목격 + 진행 기록 (지도는 나중에)
                  SectionCard(
                    title: '마지막 목격',
                    trailing: Text(
                      alert.occrDateText,
                      style: appText(
                        13,
                        weight: FontWeight.w500,
                        color: AppColors.gray600,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 160,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '지도 연동 예정',
                            style: appText(12, color: AppColors.gray400),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          alert.occrAdres,
                          style: appText(15, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 22),
                        const SectionTitle('진행 기록'),
                        Timeline(
                          entries: [
                            TimelineEntry(alert.occrDateShort, '실종경보 발령'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SourceText(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: AppButton(
                label: '182 전화',
                primary: false,
                large: true,
                onPressed: () => AppRoutes.call182(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: AppButton(
                label: '목격 제보',
                large: true,
                onPressed: () => AppRoutes.report(context, alert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
