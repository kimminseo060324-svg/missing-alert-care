import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'outfit_figure.dart';
import 'status_chip.dart';

/// 경보 목록(04)의 한 줄. 흰 상자 + 왼쪽 큰 번호.
/// [selected]는 방금 알림 온 경보 (남색 테두리).
class AlertListItem extends StatelessWidget {
  const AlertListItem({
    super.key,
    required this.alert,
    required this.number,
    this.selected = false,
    this.onTap,
  });

  final MissingAlert alert;
  final int number;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final found = alert.isFound;
    final radius = BorderRadius.circular(14);
    return Opacity(
      opacity: found ? 0.8 : 1,
      child: Material(
        color: found ? const Color(0xFFF8FBFC) : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? const BorderSide(color: AppColors.navy, width: 1.5)
              : const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    found ? '✓' : '$number',
                    style: appText(
                      20,
                      weight: FontWeight.w900,
                      color: found ? AppColors.green : AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutfitThumb(
                  alert: alert,
                  hidden: found,
                  width: 68,
                  height: 84,
                  radius: 8,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: found
                            ? StatusChip.found(alert.foundTime)
                            : const StatusChip.searching(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        found
                            ? alert.ageSex
                            : '${alert.ageSex} · ${alert.region}',
                        style: appText(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        found ? '안전하게 발견됐어요' : alert.outfitSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: appText(
                          13,
                          color: AppColors.gray600,
                          height: 1.45,
                        ),
                      ),
                      if (!found) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${alert.occrDateText} 발령',
                          style: appText(12, color: AppColors.gray400),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!found) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AppColors.gray400),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
