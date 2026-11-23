import 'package:flutter/material.dart';

/// AIRTRACE renk paleti: koyu lacivert, antrasit, elektrik mavisi.
/// Havacılık kontrol merkezi ekranlarından esinlenen, düşük göz yorgunluklu
/// koyu tema.
abstract final class AppColors {
  static const navy = Color(0xFF070D18);
  static const navyMid = Color(0xFF0C1626);
  static const anthracite = Color(0xFF151C28);
  static const panel = Color(0xFF111927);
  static const panelHigh = Color(0xFF1A2333);
  static const stroke = Color(0xFF243044);
  static const electric = Color(0xFF2F9BFF);
  static const electricBright = Color(0xFF6CC4FF);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFFB020);
  static const gold = Color(0xFFFFD166);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const textHi = Color(0xFFE6EDF7);
  static const textMid = Color(0xFF9AA8BD);
  static const textLo = Color(0xFF627089);
  static const ground = Color(0xFF7C8799);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.electric,
    onPrimary: Colors.white,
    secondary: AppColors.cyan,
    surface: AppColors.panel,
    onSurface: AppColors.textHi,
    surfaceContainerHighest: AppColors.panelHigh,
    outline: AppColors.stroke,
    error: AppColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.navy,
    canvasColor: AppColors.panel,
    dividerColor: AppColors.stroke,
    textTheme: base.textTheme.apply(bodyColor: AppColors.textHi, displayColor: AppColors.textHi),
    iconTheme: const IconThemeData(color: AppColors.textMid, size: 20),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.panelHigh, borderRadius: BorderRadius.all(Radius.circular(6))),
      textStyle: TextStyle(color: AppColors.textHi, fontSize: 12),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.anthracite,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: TextStyle(color: AppColors.textLo),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: AppColors.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: AppColors.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: AppColors.electric, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.panelHigh,
      contentTextStyle: TextStyle(color: AppColors.textHi),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.panel),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.panel),
  );
}
