import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

/// 데이터를 못 읽었을 때 보여주는 안내 + "다시 시도" 버튼.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry});

  static const message = '경보 데이터를 불러오지 못했습니다.';

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.gray400),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: appText(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: appText(13, color: AppColors.gray600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: AppButton(label: '다시 시도', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// 보여줄 경보가 없을 때 쓰는 안내 상자.
class EmptyNotice extends StatelessWidget {
  const EmptyNotice({super.key, required this.title, this.sub});

  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: appText(15, weight: FontWeight.w700),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              textAlign: TextAlign.center,
              style: appText(13, color: AppColors.gray600),
            ),
          ],
        ],
      ),
    );
  }
}
