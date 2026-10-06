import 'package:flutter/material.dart';

import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// 옷 이름에서 색을 대충 골라요. ("남색 점퍼" → 남색)
/// 나중에는 서버의 AI가 만든 옷차림 그림으로 바뀌어요.
Color? colorFromText(String text) {
  const words = <String, Color>{
    '남색': Color(0xFF26315E),
    '네이비': Color(0xFF26315E),
    '검정': Color(0xFF2B2B30),
    '검은': Color(0xFF2B2B30),
    '흰': Color(0xFFFFFFFF),
    '하얀': Color(0xFFFFFFFF),
    '회색': Color(0xFF8E8C96),
    '파란': Color(0xFF3D6FD1),
    '파랑': Color(0xFF3D6FD1),
    '하늘': Color(0xFF8EC3EE),
    '청바지': Color(0xFF4A6A9C),
    '노란': Color(0xFFF2C94C),
    '노랑': Color(0xFFF2C94C),
    '분홍': Color(0xFFF1A7C0),
    '초록': Color(0xFF4F8A5B),
    '녹색': Color(0xFF4F8A5B),
    '갈색': Color(0xFF6B4A2E),
    '베이지': Color(0xFFD9C7A7),
    '보라': Color(0xFF7E5BC9),
    '주황': Color(0xFFE58A3A),
    '형광': Color(0xFFD7F04A),
  };
  for (final e in words.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return null;
}

/// 얼굴 없는 옷차림 실루엣. 사진 대신 써요.
/// (경찰청 사진은 쓰지 않고, AI가 옷차림만 그려요.)
class OutfitFigure extends StatelessWidget {
  const OutfitFigure({super.key, required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OutfitPainter(
        top: colorFromText(alert.clothingTop) ?? AppColors.gray400,
        bottom: colorFromText(alert.clothingBottom) ?? AppColors.gray400,
        unknown: alert.clothingTop.isEmpty && alert.clothingBottom.isEmpty,
      ),
    );
  }
}

/// 목록·알림의 작은 그림 칸.
class OutfitThumb extends StatelessWidget {
  const OutfitThumb({
    super.key,
    required this.alert,
    this.width = 56,
    this.height = 64,
    this.radius = 10,
    this.hidden = false,
  });

  final MissingAlert alert;
  final double width;
  final double height;
  final double radius;

  /// 발견 완료: 개인정보 보호로 그림도 지워요.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: hidden ? AppColors.photoBg : AppColors.outfitBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: hidden ? null : OutfitFigure(alert: alert),
    );
  }
}

/// 상세 화면의 큰 그림 + "AI 생성 옷차림 그림 (얼굴 없음)" 라벨.
class OutfitPanel extends StatelessWidget {
  const OutfitPanel({super.key, required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: AppColors.outfitBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            top: 26,
            bottom: 8,
            child: OutfitFigure(alert: alert),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AI 생성 옷차림 그림 (얼굴 없음)',
                style: appText(
                  11,
                  weight: FontWeight.w700,
                  color: AppColors.purple,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitPainter extends CustomPainter {
  _OutfitPainter({
    required this.top,
    required this.bottom,
    required this.unknown,
  });

  final Color top;
  final Color bottom;
  final bool unknown;

  // 피그마 "SVG - 옷차림 그림" 좌표를 기준으로 한 그림 영역
  static const _box = Rect.fromLTWH(104, 26, 66, 122);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / _box.width) < (size.height / _box.height)
        ? size.width / _box.width
        : size.height / _box.height;
    canvas.save();
    canvas.translate(
      (size.width - _box.width * scale) / 2 - _box.left * scale,
      (size.height - _box.height * scale) / 2 - _box.top * scale,
    );
    canvas.scale(scale);

    final outline = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Paint fill(Color c) => Paint()..color = unknown ? AppColors.gray200 : c;

    void part(RRect r, Color c) {
      canvas.drawRRect(r, fill(c));
      canvas.drawRRect(r, outline);
    }

    // 머리 (얼굴 표현 없음)
    canvas.drawCircle(
      const Offset(134, 39.5),
      11.3,
      fill(const Color(0xFFD9D6DF)),
    );
    // 팔
    part(
      RRect.fromLTRBR(106.7, 56, 119.4, 94.3, const Radius.circular(6)),
      top,
    );
    part(
      RRect.fromLTRBR(153.8, 57, 166.5, 95.3, const Radius.circular(6)),
      top,
    );
    // 몸통 (상의)
    part(
      RRect.fromLTRBR(109.5, 51.8, 158.5, 97.9, const Radius.circular(10)),
      top,
    );
    // 다리 (하의)
    part(
      RRect.fromLTRBR(117, 97.9, 131.2, 139.3, const Radius.circular(3)),
      bottom,
    );
    part(
      RRect.fromLTRBR(136.8, 97.9, 150.9, 139.3, const Radius.circular(3)),
      bottom,
    );
    // 신발
    part(
      RRect.fromLTRBR(113.3, 138.4, 132.1, 145.9, const Radius.circular(4)),
      Colors.white,
    );
    part(
      RRect.fromLTRBR(135.9, 138.4, 154.7, 145.9, const Radius.circular(4)),
      Colors.white,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutfitPainter old) =>
      old.top != top || old.bottom != bottom || old.unknown != unknown;
}
