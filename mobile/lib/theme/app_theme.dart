import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansKR',
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      surface: AppColors.bg,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 52,
      foregroundColor: Colors.white,
      titleTextStyle: appText(16, weight: FontWeight.w700, color: Colors.white),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.navy,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: appText(14, color: Colors.white),
    ),
  );
}
