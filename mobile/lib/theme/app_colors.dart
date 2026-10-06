import 'package:flutter/material.dart';

/// 시안(피그마 "기억해줘 시안" > 디자인 규칙)의 색상 값.
/// 빨간색은 쓰지 않아요.
class AppColors {
  AppColors._();

  // 실종경보
  static const purple = Color(0xFF5B3FD0);
  static const purpleDeep = Color(0xFF2E2178); // 주요 버튼(CTA)
  static const purpleSoft = Color(0xFFECE8FB);
  static const purpleLine = Color(0xFFC9BEF3);

  // 발견 완료
  static const green = Color(0xFF2F7A57);
  static const greenSoft = Color(0xFFE3F2EA);

  // 일반 안전안내 / 회색
  static const generalGray = Color(0xFFECEBEF);
  static const gray900 = Color(0xFF1E1C26);
  static const gray600 = Color(0xFF5E5A6B);
  static const gray400 = Color(0xFF9A96A6);
  static const gray200 = Color(0xFFE6E4EC);
  static const gray100 = Color(0xFFF4F3F7);
  static const photoBg = Color(0xFFE2E0E8);
  static const outfitBg = Color(0xFFF0EEFA);

  static const white = Color(0xFFFFFFFF);
  static const lock = Color(0xFF22202B); // 잠금화면 배경
}
