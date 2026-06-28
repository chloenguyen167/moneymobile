import 'package:flutter/material.dart';

/// Brand palette — primary 10% · secondary 30% · background 60%
abstract final class AppColors {
  static const primary = Color(0xFFF2C300);
  static const secondary = Color(0xFF2B6490);
  static const background = Color(0xFFF6F6F6);

  static const onPrimary = Color(0xFF1A1A1A);
  static const onSecondary = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF1A1A1A);
  static const onSurfaceMuted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);

  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFE65100);
  static const error = Color(0xFFD32F2F);

  /// Chart / category palette derived from brand colors.
  static const chartPalette = [
    secondary,
    primary,
    Color(0xFF4A8BB5),
    Color(0xFFF5D547),
    Color(0xFF1E4D6B),
    Color(0xFFFFE066),
    Color(0xFF6BA3C7),
    Color(0xFF9CA3AF),
  ];
}
