import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';

/// Light/dark colour lookups for the screens that follow the SETU design
/// system, so each screen does not repeat the same `isDark ?` ternaries.
extension SetuThemeColors on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
  Color get screenBackground => isDarkTheme ? AppColors.bgApp : AppColors.lightBackground;
  Color get textPrimaryColor => isDarkTheme ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get textSecondaryColor => isDarkTheme ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get textDimColor => isDarkTheme ? AppColors.textDim : AppColors.lightTextDim;
  Color get borderColor => isDarkTheme ? AppColors.borderSubtle : AppColors.lightBorder;
}
