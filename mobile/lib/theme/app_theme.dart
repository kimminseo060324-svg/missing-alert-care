import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansKR',
    scaffoldBackgroundColor: AppColors.gray100,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      primary: AppColors.purple,
      surface: AppColors.gray100,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.gray100,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 52,
      foregroundColor: AppColors.gray600,
      titleTextStyle: appText(15, weight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.gray900,
      contentTextStyle: appText(14, color: Colors.white),
    ),
  );
}
