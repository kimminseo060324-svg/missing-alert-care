import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_button.dart';
import 'outfit_figure.dart';
import 'section_card.dart';
import 'status_chip.dart';
import 'tag_chip.dart';

/// 잠금화면 알림 카드의 공통 틀 (아이콘 · 보낸 곳 · 오른쪽 칩/시간).
class _NotiShell extends StatelessWidget {
  const _NotiShell({
    required this.icon,
    required this.iconColor,
    required this.source,
    required this.sourceColor,
    required this.trailing,
    required this.children,
    this.background = AppColors.white,
    this.borderColor,
    this.onTap,
  });

  final String icon;
  final Color iconColor;
  final String source;
  final Color sourceColor;
  final Widget trailing;
  final List<Widget> children;
  final Color background;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!, width: 2),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      icon,
                      style: appText(
                        11,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      source,
                      style: appText(
                        12,
                        weight: FontWeight.w700,
                        color: sourceColor,
                      ),
                    ),
                  ),
                  trailing,
                ],
              ),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _title(String text) =>
    Text(text, style: appText(16, weight: FontWeight.w700, height: 1.35));

Widget _sub(String text) =>
    Text(text, style: appText(13, color: AppColors.gray600, height: 1.45));

/// 일반 안전안내 (회색, 비교용)
class GeneralNotiCard extends StatelessWidget {
  const GeneralNotiCard({
    super.key,
    required this.source,
    required this.time,
    required this.title,
    required this.body,
  });

  final String source;
  final String time;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _NotiShell(
      icon: 'i',
      iconColor: AppColors.gray400,
      source: source,
      sourceColor: AppColors.gray600,
      background: AppColors.generalGray,
      trailing: Text(time, style: appText(12, color: AppColors.gray400)),
      children: [_title(title), const SizedBox(height: 6), _sub(body)],
    );
  }
}

/// 실종경보 - 접힌 알림 (01)
class AlertNotiFolded extends StatelessWidget {
  const AlertNotiFolded({super.key, required this.alert, this.onTap});

  final MissingAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _NotiShell(
      icon: '!',
      iconColor: AppColors.purple,
      source: '실종경보 · ${alert.region}',
      sourceColor: AppColors.purple,
      borderColor: AppColors.purple,
      trailing: const StatusChip.searching(),
      onTap: onTap,
      children: [
        _title('${alert.ageSex}을 찾습니다'),
        const SizedBox(height: 6),
        _sub(alert.outfitSummary),
      ],
    );
  }
}

/// 실종경보 - 펼친 알림 (02)
class AlertNotiExpanded extends StatelessWidget {
  const AlertNotiExpanded({
    super.key,
    required this.alert,
    required this.onDetail,
    required this.onReport,
  });

  final MissingAlert alert;
  final VoidCallback onDetail;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    Widget fact(String k, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: appText(11, weight: FontWeight.w500, color: AppColors.gray400),
        ),
        const SizedBox(height: 1),
        Text(v, style: appText(13, weight: FontWeight.w700)),
      ],
    );

    return _NotiShell(
      icon: '!',
      iconColor: AppColors.purple,
      source: '실종경보 · ${alert.region}',
      sourceColor: AppColors.purple,
      borderColor: AppColors.purple,
      trailing: const StatusChip.searching(),
      children: [
        _title('${alert.ageSex}을 찾습니다'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutfitThumb(alert: alert, width: 84, height: 104, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  fact('키 · 성별', '${alert.heightText} · ${alert.sexLong}'),
                  const SizedBox(height: 6),
                  fact('발생 장소', '${alert.occrAdres}\n${alert.occrDateText}'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TagWrap(
          children: [
            TagChip('상의 ${alert.topText}'),
            TagChip('하의·신발 ${alert.bottomText}'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: '상세보기',
                primary: false,
                onPressed: onDetail,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(label: '목격 제보', onPressed: onReport),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const SourceText(),
      ],
    );
  }
}

/// 실종경보 종료 - 발견 완료 알림 (03)
class FoundNotiCard extends StatelessWidget {
  const FoundNotiCard({super.key, required this.alert, this.onTap});

  final MissingAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _NotiShell(
      icon: '✓',
      iconColor: AppColors.green,
      source: '실종경보 종료 · ${alert.region}',
      sourceColor: AppColors.green,
      borderColor: AppColors.green,
      trailing: StatusChip.found(alert.foundTime),
      onTap: onTap,
      children: [
        _title('${alert.ageSex}이 안전하게 발견됐어요'),
        const SizedBox(height: 6),
        _sub('사진과 상세 정보는 개인정보 보호를 위해 삭제했어요.'),
      ],
    );
  }
}
