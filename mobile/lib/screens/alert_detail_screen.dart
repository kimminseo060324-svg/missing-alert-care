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
import '../widgets/tag_chip.dart';
import '../widgets/timeline.dart';

/// 05 실종 정보 상세 (수색 중)
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실종경보 상세')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          HeroHeader(
            label: '실종경보 · ${alert.region}',
            chip: const StatusChip.searching(tone: ChipTone.onColor),
            title: '${alert.maskedName} 씨 (${alert.sexShort}, ${alert.age}세)',
            meta: '${alert.occrDateText} 발생',
          ),
          const SizedBox(height: 12),

          // 이것만 기억하세요 (AI가 고른 핵심 3가지)
          SectionCard(
            title: '이것만 기억하세요',
            trailing: const SmallBadge('AI 선정'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SwatchTile(label: '상의', text: alert.topText),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SwatchTile(label: '하의·신발', text: alert.bottomText),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SwatchTile(label: '키', text: alert.heightText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // AI 옷차림 그림 + 인상착의
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutfitPanel(alert: alert),
                const SizedBox(height: 10),
                TagWrap(
                  children: [
                    TagChip(alert.heightText, plain: true),
                    TagChip(alert.bodyText, plain: true),
                    TagChip('상의 ${alert.topText}', plain: true),
                    TagChip('하의·신발 ${alert.bottomText}', plain: true),
                  ],
                ),
                const SizedBox(height: 10),
                const SourceText(),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 마지막 목격 (지도는 나중에)
          SectionCard(
            title: '마지막 목격 장소',
            trailing: Text(
              alert.occrDateText,
              style: appText(13, color: AppColors.gray600),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 170,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gray200, width: 1.5),
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
              ],
            ),
          ),
          const SizedBox(height: 12),

          SectionCard(
            title: '경보 진행 기록',
            child: Timeline(
              entries: [TimelineEntry(alert.occrDateShort, '실종경보 발령')],
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
