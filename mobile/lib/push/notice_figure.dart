import 'dart:math' show cos, pi, sin;
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../theme/app_colors.dart';
import '../widgets/outfit_figure.dart' show colorFromText;

/// 알림 오른쪽에 붙는 작은 옷차림 그림 (얼굴 없음).
///
/// 앱이 꺼져 있을 때도 그려야 해서 화면 그리기 기능 없이 점을 직접 찍어요.
/// 결과는 BMP 그림 파일 바이트예요. Android가 그대로 읽어요.
class NoticeFigure {
  const NoticeFigure({this.top, this.bottom, this.shoe});

  final Color? top;
  final Color? bottom;
  final Color? shoe;

  /// 상의·하의 색을 하나도 모르면 그림을 붙이지 않아요.
  bool get hasColor => top != null || bottom != null;

  static final _shoeWords = RegExp('운동화|신발|구두|샌들|부츠|슬리퍼|단화');
  static final _bottomWords = RegExp('바지|청바지|치마|스커트|레깅스|슬랙스');

  /// AI 요약 문장들로 색을 정해요. ("회색 점퍼", "검정 바지", "흰 운동화")
  /// 신발 말이 있으면 신발, 바지·치마 같은 말이 있으면 하의,
  /// 남은 문장 중 색 말이 있는 첫 문장이 상의예요.
  factory NoticeFigure.fromSummary(List<String> summary) {
    String? top, bottom, shoe;
    for (final s in summary) {
      if (_shoeWords.hasMatch(s)) {
        shoe ??= s;
      } else if (_bottomWords.hasMatch(s)) {
        bottom ??= s;
      } else if (colorFromText(s) != null) {
        top ??= s;
      }
    }
    Color? color(String? s) => s == null ? null : colorFromText(s);
    return NoticeFigure(
      top: color(top),
      bottom: color(bottom),
      shoe: color(shoe),
    );
  }

  static const _skin = Color(0xFFD9D6DF);
  static const _unknown = AppColors.gray400;
  static const _defaultShoe = Color(0xFF4A4A52);

  /// [size] x [size] 크기 24비트 BMP 바이트.
  Uint8List toBmp({int size = 128}) {
    // 그림 좌표는 상세 화면 그림과 같은 가로 100 x 세로 212를 줄여서 써요.
    final scale = size * 0.9 / 212;
    final offsetX = (size - 100 * scale) / 2;
    final offsetY = (size - 212 * scale) / 2;
    final shapes = <(List<List<double>>, Color)>[
      (_leftArm, top ?? _unknown),
      (_rightArm, top ?? _unknown),
      (_pants, bottom ?? _unknown),
      (_leftShoe, shoe ?? _defaultShoe),
      (_rightShoe, shoe ?? _defaultShoe),
      (_body, top ?? _unknown),
      (_neck, _skin),
      (_head, _skin),
    ];

    const sub = 3; // 한 점을 3 x 3으로 나눠서 가장자리를 부드럽게
    final rowBytes = size * 3; // 128 x 3은 4의 배수라 줄 끝 채움이 없어요
    final pixels = Uint8List(rowBytes * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var sy = 0; sy < sub; sy++) {
          for (var sx = 0; sx < sub; sx++) {
            final px = (x + (sx + 0.5) / sub - offsetX) / scale;
            final py = (y + (sy + 0.5) / sub - offsetY) / scale;
            var c = AppColors.bg;
            for (final (poly, color) in shapes) {
              if (_inside(poly, px, py)) c = color;
            }
            r += c.r;
            g += c.g;
            b += c.b;
          }
        }
        const n = sub * sub;
        // BMP는 아래 줄부터, 파랑·초록·빨강 순서로 써요.
        final i = (size - 1 - y) * rowBytes + x * 3;
        pixels[i] = (b / n * 255).round();
        pixels[i + 1] = (g / n * 255).round();
        pixels[i + 2] = (r / n * 255).round();
      }
    }

    final header = ByteData(54)
      ..setUint8(0, 0x42) // 'B'
      ..setUint8(1, 0x4D) // 'M'
      ..setUint32(2, 54 + pixels.length, Endian.little)
      ..setUint32(10, 54, Endian.little)
      ..setUint32(14, 40, Endian.little)
      ..setInt32(18, size, Endian.little)
      ..setInt32(22, size, Endian.little)
      ..setUint16(26, 1, Endian.little)
      ..setUint16(28, 24, Endian.little)
      ..setUint32(34, pixels.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...pixels]);
  }

  static bool _inside(List<List<double>> poly, double x, double y) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final (xi, yi, xj, yj) = (poly[i][0], poly[i][1], poly[j][0], poly[j][1]);
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  static List<List<double>> _oval(double l, double t, double r, double b) {
    const steps = 24;
    final cx = (l + r) / 2,
        cy = (t + b) / 2,
        rx = (r - l) / 2,
        ry = (b - t) / 2;
    return [
      for (var i = 0; i < steps; i++)
        [cx + rx * cos(2 * pi * i / steps), cy + ry * sin(2 * pi * i / steps)],
    ];
  }

  // 상세 화면 그림(OutfitFigure)과 같은 자리. 곡선은 점 몇 개로 줄였어요.
  static const _leftArm = [
    [27.0, 47.0],
    [21.0, 52.0],
    [19.0, 60.0],
    [14.0, 104.0],
    [18.0, 107.0],
    [22.0, 105.0],
    [29.0, 64.0],
  ];
  static const _rightArm = [
    [73.0, 47.0],
    [79.0, 52.0],
    [81.0, 60.0],
    [86.0, 104.0],
    [82.0, 107.0],
    [78.0, 105.0],
    [71.0, 64.0],
  ];
  static const _pants = [
    [30.0, 104.0],
    [70.0, 104.0],
    [71.0, 196.0],
    [53.0, 196.0],
    [50.5, 128.0],
    [49.5, 128.0],
    [47.0, 196.0],
    [29.0, 196.0],
  ];
  static const _leftShoe = [
    [27.0, 194.0],
    [46.0, 194.0],
    [48.0, 198.0],
    [46.0, 203.0],
    [27.0, 203.0],
    [25.0, 198.0],
  ];
  static const _rightShoe = [
    [54.0, 194.0],
    [73.0, 194.0],
    [75.0, 198.0],
    [73.0, 203.0],
    [54.0, 203.0],
    [52.0, 198.0],
  ];
  static const _body = [
    [40.0, 40.0],
    [60.0, 40.0],
    [69.0, 42.0],
    [74.0, 46.0],
    [75.0, 52.0],
    [72.0, 110.0],
    [50.0, 112.0],
    [28.0, 110.0],
    [25.0, 52.0],
    [26.0, 46.0],
    [31.0, 42.0],
  ];
  static const _neck = [
    [45.0, 30.0],
    [55.0, 30.0],
    [55.0, 42.0],
    [45.0, 42.0],
  ];
  static final _head = _oval(38, 4, 62, 32);
}
