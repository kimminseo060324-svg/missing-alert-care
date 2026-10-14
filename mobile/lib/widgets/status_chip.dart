import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

enum ChipTone { searching, found, ended, onColor }

/// "● 수색 중" / "✓ 발견 완료 (14:35)" / "● 경보 종료" 상태 라벨.
class StatusChip extends StatelessWidget {
  const StatusChip.searching({super.key, this.tone = ChipTone.searching})
    : _status = AlertStatus.searching,
      foundTime = null;

  const StatusChip.found(String time, {super.key, this.tone = ChipTone.found})
    : _status = AlertStatus.found,
      foundTime = time;

  const StatusChip.ended({super.key, this.tone = ChipTone.ended})
    : _status = AlertStatus.ended,
      foundTime = null;

  /// 경보 상태에 맞는 라벨. [onColor]면 남색·초록 머리 위에 쓰는 흰 글씨 라벨.
  factory StatusChip.of(MissingAlert alert, {bool onColor = false}) {
    const color = ChipTone.onColor;
    return switch (alert.status) {
      AlertStatus.searching =>
        onColor
            ? const StatusChip.searching(tone: color)
            : const StatusChip.searching(),
      AlertStatus.ended =>
        onColor
            ? const StatusChip.ended(tone: color)
            : const StatusChip.ended(),
      AlertStatus.found =>
        onColor
            ? StatusChip.found(alert.foundTime, tone: color)
            : StatusChip.found(alert.foundTime),
    };
  }

  final AlertStatus _status;
  final String? foundTime;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.searching => (AppColors.navySoft, AppColors.navy),
      ChipTone.found => (AppColors.greenSoft, AppColors.green),
      ChipTone.ended => (AppColors.generalGray, AppColors.gray600),
      ChipTone.onColor => (Colors.white.withValues(alpha: 0.16), Colors.white),
    };
    final isFound = _status == AlertStatus.found;
    final label = switch (_status) {
      AlertStatus.searching => '수색 중',
      AlertStatus.ended => '경보 종료',
      AlertStatus.found =>
        (foundTime ?? '').isEmpty ? '발견 완료' : '발견 완료 ($foundTime)',
    };

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFound)
            Text(
              '✓',
              style: appText(11, weight: FontWeight.w700, color: fg),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: appText(12, weight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
