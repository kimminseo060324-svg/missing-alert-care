import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 화면 맨 위 색깔 머리 (수색 중 = 남색, 발견 완료 = 초록).
/// 상태바까지 칠하고, 제목 줄 아래에 [child]를 넣어요.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.child,
    this.found = false,
    this.centerTitle = true,
    this.showBack = true,
  });

  final String title;
  final Widget? child;
  final bool found;
  final bool centerTitle;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    final titleText = Text(
      title,
      style: appText(16, weight: FontWeight.w700, color: Colors.white),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        width: double.infinity,
        color: found ? AppColors.green : AppColors.navy,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: centerTitle
                    ? Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: canPop ? _BackButton() : null,
                          ),
                          Expanded(child: Center(child: titleText)),
                          const SizedBox(width: 52),
                        ],
                      )
                    : Row(
                        children: [
                          if (canPop)
                            _BackButton()
                          else
                            const SizedBox(width: 22),
                          titleText,
                        ],
                      ),
              ),
              if (child != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
      tooltip: '뒤로',
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// 머리 안의 요약: 상태 라벨 · 이름 · 작은 글 두 줄.
class HeroInfo extends StatelessWidget {
  const HeroInfo({
    super.key,
    required this.chip,
    required this.title,
    this.sub,
    required this.meta,
  });

  final Widget chip;
  final String title;
  final String? sub;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PillAlign(child: chip),
        const SizedBox(height: 6),
        Text(
          title,
          style: appText(22, weight: FontWeight.w800, color: Colors.white),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            style: appText(15, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          meta,
          style: appText(12, color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}

/// 알약 모양(칩)은 안쪽 여백만큼 왼쪽으로 당겨서,
/// 칩 안의 글자가 아래 큰 글자와 같은 줄에 서게 해요.
class PillAlign extends StatelessWidget {
  const PillAlign({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(offset: const Offset(-10, 0), child: child);
  }
}
