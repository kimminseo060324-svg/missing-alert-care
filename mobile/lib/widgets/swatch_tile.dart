import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'outfit_figure.dart';

/// "이것만 기억하세요"의 한 칸: 가운데 둥근 색 네모 + 굵은 글.
/// 색을 알 수 없으면 네모 안에 [label] 첫 글자를 써요.
class SwatchTile extends StatelessWidget {
  const SwatchTile({
    super.key,
    required this.label,
    required this.text,
    this.size = 48,
    this.fontSize = 16,
  });

  final String label; // 상의 / 하의·신발 / 키
  final String text;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = colorFromText(text);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ColorSquare(color: color, size: size, fallback: label),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: appText(fontSize, weight: FontWeight.w800, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// 둥근 색 네모. 색이 없으면 흰 네모에 글자 하나.
class ColorSquare extends StatelessWidget {
  const ColorSquare({
    super.key,
    required this.color,
    required this.size,
    required this.fallback,
  });

  final Color? color;
  final double size;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? AppColors.white,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.14)),
      ),
      child: color == null
          ? Text(
              fallback.substring(0, 1),
              style: appText(
                size / 3,
                weight: FontWeight.w700,
                color: AppColors.gray400,
              ),
            )
          : null,
    );
  }
}
