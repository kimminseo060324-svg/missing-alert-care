import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 진한 보라(primary) 또는 흰색 테두리(outline) 버튼.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return SizedBox(
      height: large ? 52 : 44,
      width: double.infinity,
      child: Material(
        color: primary ? AppColors.purpleDeep : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: primary
              ? BorderSide.none
              : const BorderSide(color: AppColors.gray200),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: appText(
                large ? 16 : 14,
                weight: FontWeight.w700,
                color: primary ? Colors.white : AppColors.gray900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 맨 아래에 붙는 흰색 버튼 영역.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.gray200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(top: false, child: child),
    );
  }
}
