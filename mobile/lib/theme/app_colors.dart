import 'package:flutter/material.dart';

/// 피그마 "기억해줘 시안" > 통일 디자인 (큰 번호형) 색상.
/// 남색은 주 색, 초록은 발견 완료에만 써요. 빨간색은 쓰지 않아요.
class AppColors {
  AppColors._();

  // 실종경보 (주 색)
  static const navy = Color(0xFF121D64); // 윗부분 배경, 큰 번호, 주 버튼
  static const navySoft = Color(0xFFE5E7F1); // 수색 중 라벨, 정리된 제보 상자

  // 발견 완료
  static const green = Color(0xFF1A8A55);
  static const greenSoft = Color(0xFFE2F3EA);

  // 바탕 · 상자
  static const bg = Color(0xFFF1F7F9); // 화면 바탕, 상자 안 칸
  static const white = Color(0xFFFFFFFF); // 상자
  static const border = Color(0xFFE1E9ED); // 흰 상자 테두리
  static const line = Color(0xFFDCE5EA); // 구분선

  // 글자
  static const ink = Color(0xFF141414);
  static const gray600 = Color(0xFF4D5860);
  static const gray400 = Color(0xFF738088);

  // 일반 안전안내 알림 (회색)
  static const generalGray = Color(0xFFE3E8EB);

  // 잠금화면 배경 (위 → 아래)
  static const lockTop = Color(0xFF1B2140);
  static const lockBottom = Color(0xFF10142A);
}
