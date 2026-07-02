import 'package:flutter/material.dart';

/// Shell-specific layout and visual constants for nav/header chrome.
abstract final class ShellTokens {
  static const double navWidth = 240;

  /// Visible width when the sidebar is collapsed (icons only).
  ///
  /// [iconInsetFromNavEdge] + [itemIconSize] + [itemHorizontalPadding] yields 52;
  /// the extra 4 logical pixels keep the icon footprint clear of the clip edge.
  static const double navCollapsedWidth = 56;

  /// Horizontal offset of nav item icons from the nav's left edge.
  static const double iconInsetFromNavEdge = 24;

  static const double headerHeight = 52;
  static const double headerAvatarSize = 32;
  static const double headerIconButtonSize = 32;
  static const double headerActionsGap = 12;

  /// Inset between the nav edge and the content panel (leading and below header only).
  static const double contentPanelInset = 12;
  static const double itemHeight = 34;
  static const double itemRadius = 10;
  static const double itemIconSize = 18;
  static const double itemHorizontalPadding = 10;
  static const Duration hoverDuration = Duration(milliseconds: 180);
  static const Duration expandDuration = Duration(milliseconds: 250);
  static const Duration collapseDuration = Duration(milliseconds: 250);

  static const Color badgeWarningBackground = Color(0xFFFFD8C0);
  static const Color badgeSuccessBackground = Color(0xFFCFF2E5);
}
