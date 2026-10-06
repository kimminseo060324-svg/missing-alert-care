import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'outfit_figure.dart';

/// "이것만 기억하세요"의 한 칸: 색 견본 + 짧은 글.
class SwatchTile extends StatelessWidget {
  const SwatchTile({super.key, required this.label, required this.text});

  final String label; // 상의 / 하의·신발 / 키
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = colorFromText(text);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color ?? AppColors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gray200),
            ),
            child: color == null
                ? Center(
                    child: Text(
                      label.substring(0, 1),
                      style: appText(
                        12,
                        weight: FontWeight.w700,
                        color: AppColors.gray400,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Text(label, style: appText(11, color: AppColors.gray400)),
          const SizedBox(height: 2),
          Text(
            text,
            textAlign: TextAlign.center,
            style: appText(13, weight: FontWeight.w700, height: 1.3),
          ),
        ],
      ),
    );
  }
}
