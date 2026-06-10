import 'package:flutter/material.dart';

/// Shell-specific layout and visual constants for nav/header chrome.
abstract final class ShellTokens {
  static const double navWidth = 260;

  /// Visible width when the sidebar is collapsed (icons only).
  ///
  /// Matches [iconInsetFromNavEdge] + [itemIconSize] + [itemHorizontalPadding].
  static const double navCollapsedWidth = 64;

  /// Horizontal offset of nav item icons from the nav's left edge.
  static const double iconInsetFromNavEdge = 28;

  static const double headerHeight = 64;
  static const double headerSearchMaxWidth = 480;
  static const double headerAvatarSize = 40;
  static const double headerIconButtonSize = 40;
  static const double headerActionsGap = 16;

  /// Inset between the nav edge and the floating content panel.
  static const double contentPanelInset = 16;
  static const double itemHeight = 40;
  static const double itemRadius = 12;
  static const double itemIconSize = 20;
  static const double itemHorizontalPadding = 12;
  static const Duration hoverDuration = Duration(milliseconds: 180);
  static const Duration expandDuration = Duration(milliseconds: 250);
  static const Duration collapseDuration = Duration(milliseconds: 250);

  static const Color badgeWarningBackground = Color(0xFFFFD8C0);
  static const Color badgeSuccessBackground = Color(0xFFCFF2E5);
}
