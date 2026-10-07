import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 글자 스타일. Noto Sans KR 가변 글꼴이라 굵기(wght)를 직접 넣어 줘요.
TextStyle appText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'NotoSansKR',
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
  );
}
