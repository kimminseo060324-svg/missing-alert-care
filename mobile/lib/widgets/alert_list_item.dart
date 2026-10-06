import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'outfit_figure.dart';
import 'status_chip.dart';

/// 경보 목록(04)의 한 줄.
class AlertListItem extends StatelessWidget {
  const AlertListItem({
    super.key,
    required this.alert,
    this.selected = false,
    this.onTap,
  });

  final MissingAlert alert;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final found = alert.isFound;
    final radius = BorderRadius.circular(16);
    return Opacity(
      opacity: found ? 0.75 : 1,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? const BorderSide(color: AppColors.purple, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                OutfitThumb(alert: alert, hidden: found),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      found
                          ? StatusChip.found(alert.foundTime)
                          : const StatusChip.searching(),
                      const SizedBox(height: 3),
                      Text(
                        found
                            ? alert.ageSex
                            : '${alert.ageSex} · ${alert.region}',
                        style: appText(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        found ? '안전하게 발견됐어요' : alert.outfitSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(12, color: AppColors.gray600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
