import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 인상착의 태그. 보라색(핵심 특징) 또는 회색(plain).
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.plain = false});

  final String label;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: plain ? AppColors.gray100 : AppColors.purpleSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: appText(
            13,
            weight: plain ? FontWeight.w500 : FontWeight.w700,
            color: plain ? AppColors.gray900 : AppColors.purpleDeep,
          ),
        ),
      ),
    );
  }
}

class TagWrap extends StatelessWidget {
  const TagWrap({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}
