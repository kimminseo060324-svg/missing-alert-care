import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 상세 화면 맨 위 색깔 카드 (수색 중 = 보라, 발견 완료 = 초록).
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.label,
    required this.chip,
    required this.title,
    required this.meta,
    this.found = false,
  });

  final String label;
  final Widget chip;
  final String title;
  final String meta;
  final bool found;

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.9);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: found ? AppColors.green : AppColors.purple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: appText(12, color: soft)),
              ),
              chip,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: appText(22, weight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: appText(12, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}
