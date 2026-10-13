import 'package:flutter/material.dart';

/// 알림 아이콘의 사람 모양 선 (왼 어깨 → 머리 → 오른 어깨).
class PersonMark extends StatelessWidget {
  const PersonMark({super.key, this.size = 14, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PersonPainter(color));
}

class _PersonPainter extends CustomPainter {
  _PersonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 원본 그림(120칸) 중 사람 모양이 있는 28~92칸을 아이콘 크기에 맞춰요.
    final s = size.width / 72;
    canvas.translate(
      (size.width - 64 * s) / 2 - 28 * s,
      (size.height - 65 * s) / 2 - 33 * s,
    );
    canvas.scale(s);
    final path = Path()
      ..moveTo(28, 98)
      ..cubicTo(28, 80, 39, 68, 52, 65)
      ..arcToPoint(
        const Offset(68, 65),
        radius: const Radius.circular(16),
        largeArc: true,
      )
      ..cubicTo(81, 68, 92, 80, 92, 98);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PersonPainter old) => old.color != color;
}

/// 처음 보일 때 한 번 살짝 커졌다 작아져요 (깜빡 느낌).
class PulseOnce extends StatefulWidget {
  const PulseOnce({super.key, required this.child});

  final Widget child;

  @override
  State<PulseOnce> createState() => _PulseOnceState();
}

class _PulseOnceState extends State<PulseOnce>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.14,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.14,
        end: 0.97,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.97,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 25,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
