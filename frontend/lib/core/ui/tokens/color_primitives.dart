import 'package:flutter/material.dart';

/// Raw palette values — never consumed directly by feature components.
abstract final class AppColorPrimitives {
  // Neutrals
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral25 = Color(0xFFFAFBFC);
  static const Color neutral50 = Color(0xFFF4F6F9);
  static const Color neutral100 = Color(0xFFECEFF3);
  static const Color neutral150 = Color(0xFFE2E7EE);
  static const Color neutral200 = Color(0xFFD5DCE5);
  static const Color neutral300 = Color(0xFFC0C9D4);
  static const Color neutral400 = Color(0xFF9AA6B4);
  static const Color neutral500 = Color(0xFF75828F);
  static const Color neutral600 = Color(0xFF55606D);
  static const Color neutral700 = Color(0xFF3C4652);
  static const Color neutral800 = Color(0xFF28303A);
  static const Color neutral900 = Color(0xFF1A2029);
  static const Color neutral950 = Color(0xFF0E1116);

  // Teal
  static const Color teal50 = Color(0xFFE6F7F7);
  static const Color teal100 = Color(0xFFC4ECEC);
  static const Color teal200 = Color(0xFF93DBDC);
  static const Color teal300 = Color(0xFF5BC4C6);
  static const Color teal400 = Color(0xFF2BA7AB);
  static const Color teal500 = Color(0xFF0E8A8F);
  static const Color teal600 = Color(0xFF0B7075);
  static const Color teal700 = Color(0xFF0A5B5F);
  static const Color teal800 = Color(0xFF0A494C);
  static const Color teal900 = Color(0xFF093B3E);

  // Violet
  static const Color violet50 = Color(0xFFEEEAFE);
  static const Color violet100 = Color(0xFFDAD4FC);
  static const Color violet200 = Color(0xFFBBB0F9);
  static const Color violet300 = Color(0xFF9A8BF4);
  static const Color violet400 = Color(0xFF7D6BEE);
  static const Color violet500 = Color(0xFF6A54E6);
  static const Color violet600 = Color(0xFF573FD1);
  static const Color violet700 = Color(0xFF4632AB);
  static const Color violet800 = Color(0xFF382889);
  static const Color violet900 = Color(0xFF2C1F6B);

  // Green
  static const Color green50 = Color(0xFFE7F6ED);
  static const Color green100 = Color(0xFFC6E9D2);
  static const Color green500 = Color(0xFF1F9D57);
  static const Color green600 = Color(0xFF167E45);
  static const Color green700 = Color(0xFF0F5E34);

  // Amber
  static const Color amber50 = Color(0xFFFBF1DF);
  static const Color amber100 = Color(0xFFF6E0B8);
  static const Color amber500 = Color(0xFFC77F0A);
  static const Color amber600 = Color(0xFFA5650A);
  static const Color amber700 = Color(0xFF855009);

  // Red
  static const Color red50 = Color(0xFFFBECEC);
  static const Color red100 = Color(0xFFF6CFCF);
  static const Color red500 = Color(0xFFD64545);
  static const Color red600 = Color(0xFFBC3333);
  static const Color red700 = Color(0xFF9A2828);

  // Blue
  static const Color blue50 = Color(0xFFE8F0FE);
  static const Color blue100 = Color(0xFFC7DBFB);
  static const Color blue500 = Color(0xFF2D7FF9);
  static const Color blue600 = Color(0xFF1C63D6);
  static const Color blue700 = Color(0xFF164FAB);

  // Dark-theme-only semantic hex values (not in primitive scale).
  static const Color darkSurfaceDefault = Color(0xFF161B22);
  static const Color darkSurfaceRaised = Color(0xFF1C232C);
  static const Color darkSurfaceSunken = Color(0xFF0B0E13);
  static const Color darkSurfaceMuted = Color(0xFF222A34);
  static const Color darkSurfaceHover = Color(0xFF20272F);
  static const Color darkSurfaceSelected = Color(0xFF0E2B2C);
  static const Color darkSurfaceAi = Color(0xFF1B1638);
  static const Color darkTextPrimary = Color(0xFFE6EBF2);
  static const Color darkTextSecondary = Color(0xFFA9B4C0);
  static const Color darkTextTertiary = Color(0xFF7C8896);
  static const Color darkTextPlaceholder = Color(0xFF5C6773);
  static const Color darkTextDisabled = Color(0xFF4E5866);
  static const Color darkIconDefault = Color(0xFFA9B4C0);
  static const Color darkIconMuted = Color(0xFF6B7684);
  static const Color darkBorderSubtle = Color(0xFF232B35);
  static const Color darkBorderDefault = Color(0xFF2C3542);
  static const Color darkBorderStrong = Color(0xFF3A4553);
  static const Color darkStatusSuccessFg = Color(0xFF5FD495);
  static const Color darkStatusSuccessSurface = Color(0xFF0E2A1B);
  static const Color darkStatusSuccessBorder = Color(0xFF1C4230);
  static const Color darkStatusWarningFg = Color(0xFFE9B45A);
  static const Color darkStatusWarningSurface = Color(0xFF2E2109);
  static const Color darkStatusWarningBorder = Color(0xFF4A3712);
  static const Color darkStatusDangerFg = Color(0xFFF08A8A);
  static const Color darkStatusDangerSurface = Color(0xFF2E1414);
  static const Color darkStatusDangerBorder = Color(0xFF4A2323);
  static const Color darkStatusInfoFg = Color(0xFF7FB0FB);
  static const Color darkStatusInfoSurface = Color(0xFF0F1F3A);
  static const Color darkStatusInfoBorder = Color(0xFF1E355C);
  static const Color darkActionDangerHover = Color(0xFFF08A8A);
  static const Color darkActionDangerActive = Color(0xFFF08A8A);

  static Color rgba(int r, int g, int b, double a) =>
      Color.fromRGBO(r, g, b, a);
}
