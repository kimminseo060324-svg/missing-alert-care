import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

enum ChipTone { searching, found, onColor }

/// "● 수색 중" / "✓ 발견 완료 (14:35)" 상태 칩. 카드 오른쪽 위에 둬요.
class StatusChip extends StatelessWidget {
  const StatusChip.searching({super.key, this.tone = ChipTone.searching})
    : foundTime = null;

  const StatusChip.found(String time, {super.key, this.tone = ChipTone.found})
    : foundTime = time;

  final String? foundTime;
  final ChipTone tone;

  bool get _isFound => foundTime != null;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.searching => (AppColors.purpleSoft, AppColors.purple),
      ChipTone.found => (AppColors.greenSoft, AppColors.green),
      ChipTone.onColor => (Colors.white.withValues(alpha: 0.18), Colors.white),
    };
    final label = _isFound ? '발견 완료 ($foundTime)' : '수색 중';

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
          if (_isFound)
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
          const SizedBox(width: 4),
          Text(
            label,
            style: appText(12, weight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
