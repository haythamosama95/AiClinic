import 'package:flutter/material.dart';

/// Shell-specific layout and visual constants for nav/header chrome.
abstract final class ShellTokens {
  static const double navWidth = 260;
  static const double headerHeight = 64;
  static const double itemHeight = 40;
  static const double itemRadius = 12;
  static const double itemIconSize = 20;
  static const double itemHorizontalPadding = 12;
  static const double logoSize = 40;
  static const Duration hoverDuration = Duration(milliseconds: 180);

  static const Color badgeWarningBackground = Color(0xFFFFD8C0);
  static const Color badgeSuccessBackground = Color(0xFFCFF2E5);
}
