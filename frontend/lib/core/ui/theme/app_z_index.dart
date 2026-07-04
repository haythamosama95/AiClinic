/// Z-index scale matching `--z-*` design tokens.
///
/// Flutter overlays are ordered by insertion; use these values when a widget
/// exposes an explicit stacking index (e.g. [Material.elevation] on web parity).
abstract final class AppZIndex {
  static const int base = 0;
  static const int sticky = 1000;
  static const int dropdown = 1100;
  static const int backdrop = 1200;
  static const int modal = 1300;
  static const int popover = 1400;
  static const int toast = 1500;
  static const int tooltip = 1600;
  static const int command = 1700;
}
