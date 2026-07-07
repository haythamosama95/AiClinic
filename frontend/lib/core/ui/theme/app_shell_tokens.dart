/// Shell layout tokens (`02-tokens` §11, default comfortable density).
abstract final class AppShellTokens {
  static const topBarHeight = 56.0;

  /// Shared height for command trigger, branch switcher, and trailing icon controls.
  static const topBarActionHeight = 40.0;
  static const navItemHeight = 36.0;
  static const sidebarExpandedWidth = 248.0;
  static const sidebarCollapsedWidth = 56.0;
  static const contentMaxWidth = 1152.0; // max-w-6xl
  static const collapseDuration = Duration(milliseconds: 200);
}
