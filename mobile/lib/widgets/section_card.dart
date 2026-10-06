import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 흰색 둥근 카드. 제목(선택)과 오른쪽 작은 글씨(선택)를 가질 수 있어요.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.color = AppColors.white,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: appText(14, weight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// 카드 제목 옆의 작은 보라색 배지 (예: "AI 선정").
class SmallBadge extends StatelessWidget {
  const SmallBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.purpleSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: appText(11, weight: FontWeight.w700, color: AppColors.purple),
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
