import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 남색(primary) 또는 흰색에 검은 테두리(outline) 버튼.
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
    final radius = BorderRadius.circular(8);
    return SizedBox(
      height: large ? 52 : 46,
      width: double.infinity,
      child: Material(
        color: primary ? AppColors.navy : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: primary
              ? BorderSide.none
              : const BorderSide(color: AppColors.ink, width: 1.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: appText(
                large ? 16 : 15,
                weight: FontWeight.w700,
                color: primary ? Colors.white : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 맨 아래 버튼 영역 (바탕색 + 위쪽 얇은 줄).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(top: false, child: child),
    );
  }
}
