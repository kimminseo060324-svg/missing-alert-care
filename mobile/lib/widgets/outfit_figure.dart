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

/// 신발 색: "흰 운동화"처럼 신발 앞에 색이 있으면 그 색, 없으면 진회색.
Color _shoeColor(String text) {
  final m = RegExp(r'(\S+)\s*(운동화|신발|구두|샌들|부츠|슬리퍼)').firstMatch(text);
  return (m == null ? null : colorFromText(m.group(1)!)) ??
      const Color(0xFF4A4A52);
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
        shoe: _shoeColor(alert.clothingBottom),
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
        color: AppColors.bg,
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
        color: AppColors.bg,
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
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AI 생성 옷차림 그림 (얼굴 없음)',
                style: appText(
                  11,
                  weight: FontWeight.w700,
                  color: AppColors.navy,
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
    required this.shoe,
    required this.unknown,
  });

  final Color top;
  final Color bottom;
  final Color shoe;
  final bool unknown;

  // 그림 좌표 (가로 100 x 세로 212)
  static const _box = Rect.fromLTWH(0, 0, 100, 212);
  static const _skin = Color(0xFFD9D6DF);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / _box.width) < (size.height / _box.height)
        ? size.width / _box.width
        : size.height / _box.height;
    canvas.save();
    canvas.translate(
      (size.width - _box.width * scale) / 2,
      (size.height - _box.height * scale) / 2,
    );
    canvas.scale(scale);

    final outline = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
    Paint fill(Color c) => Paint()
      ..color = unknown ? AppColors.line : c
      ..isAntiAlias = true;
    void draw(Path p, Color c) {
      canvas.drawPath(p, fill(c));
      canvas.drawPath(p, outline);
    }

    // 바닥 그림자
    canvas.drawOval(
      const Rect.fromLTRB(22, 202, 78, 210),
      Paint()..color = const Color(0x14000000),
    );

    // 팔 (소매 = 상의 색) + 손
    final leftArm = Path()
      ..moveTo(27, 47)
      ..quadraticBezierTo(20, 50, 19, 60)
      ..lineTo(14, 104)
      ..quadraticBezierTo(18, 108, 22, 105)
      ..lineTo(29, 64)
      ..close();
    final rightArm = Path()
      ..moveTo(73, 47)
      ..quadraticBezierTo(80, 50, 81, 60)
      ..lineTo(86, 104)
      ..quadraticBezierTo(82, 108, 78, 105)
      ..lineTo(71, 64)
      ..close();
    draw(leftArm, top);
    draw(rightArm, top);
    canvas.drawCircle(const Offset(17.5, 110), 4.5, fill(_skin));
    canvas.drawCircle(const Offset(82.5, 110), 4.5, fill(_skin));

    // 하의 (허리 + 두 다리)
    final pants = Path()
      ..moveTo(30, 104)
      ..lineTo(70, 104)
      ..lineTo(71, 196)
      ..lineTo(53, 196)
      ..lineTo(50.5, 128)
      ..lineTo(49.5, 128)
      ..lineTo(47, 196)
      ..lineTo(29, 196)
      ..close();
    draw(pants, bottom);

    // 신발
    final leftShoe = Path()
      ..addRRect(
        RRect.fromLTRBR(25, 194, 48, 203, const Radius.circular(4.5)),
      );
    final rightShoe = Path()
      ..addRRect(
        RRect.fromLTRBR(52, 194, 75, 203, const Radius.circular(4.5)),
      );
    draw(leftShoe, shoe);
    draw(rightShoe, shoe);

    // 상의 (어깨가 둥근 몸통)
    final body = Path()
      ..moveTo(40, 40)
      ..lineTo(60, 40)
      ..cubicTo(68, 41, 74, 44, 75, 52)
      ..lineTo(72, 110)
      ..quadraticBezierTo(50, 113, 28, 110)
      ..lineTo(25, 52)
      ..cubicTo(26, 44, 32, 41, 40, 40)
      ..close();
    draw(body, top);

    // 목 + 머리 (얼굴 표현 없음)
    canvas.drawRRect(
      RRect.fromLTRBR(45, 30, 55, 42, const Radius.circular(3)),
      fill(_skin),
    );
    canvas.drawOval(const Rect.fromLTRB(38, 4, 62, 32), fill(_skin));
    canvas.drawOval(const Rect.fromLTRB(38, 4, 62, 32), outline);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutfitPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.shoe != shoe ||
      old.unknown != unknown;
}
