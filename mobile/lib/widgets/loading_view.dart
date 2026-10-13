import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 불러오는 중: 연한 바탕 위 가운데에 집 로딩 그림 + "불러오는 중이에요".
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  static const message = '불러오는 중이에요';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width * 0.26;
    return ColoredBox(
      color: AppColors.bg.withValues(alpha: 0.93),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/loading_house.webp',
              width: size,
              height: size,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 8),
            Text(message, style: appText(15, color: AppColors.gray600)),
          ],
        ),
      ),
    );
  }
}
