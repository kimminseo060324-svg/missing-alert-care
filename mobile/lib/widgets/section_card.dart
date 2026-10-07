import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 흰 상자. 제목(선택) 아래에 얇은 줄이 들어가요.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.color = AppColors.white,
    this.titleColor = AppColors.ink,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final Color color;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final plain = color == AppColors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: plain ? Border.all(color: AppColors.border) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            SectionTitle(title!, trailing: trailing, color: titleColor),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// 상자 안 제목 줄 (아래에 얇은 구분선).
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.color = AppColors.ink,
  });

  final String title;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: appText(14, weight: FontWeight.w700, color: color),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 연한 바탕 작은 칸 (키 168cm 처럼 이름 + 값).
class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: appText(12, color: AppColors.gray400)),
          const SizedBox(height: 2),
          Text(value, style: appText(14, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// "자료 출처: 경찰청 · 행안부 재난문자"
class SourceText extends StatelessWidget {
  const SourceText({super.key, this.center = false});

  static const text = '자료 출처: 경찰청 · 행안부 재난문자';

  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: appText(11, color: AppColors.gray400),
    );
  }
}
