import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Minimum menu width (web `min-w-[12rem]`).
const _kMenuMinWidth = 192.0;

// ---------------------------------------------------------------------------
// Entry model (web `MenuEntry` tagged union)
// ---------------------------------------------------------------------------

/// Tagged union of menu rows consumable by [AppMenu] and [AppContextMenu].
sealed class AppMenuEntry {
  const AppMenuEntry();
}

/// Action row with optional icon, shortcut, checked, destructive, and disabled states.
final class AppMenuItem extends AppMenuEntry {
  const AppMenuItem({
    required this.id,
    required this.label,
    this.icon,
    this.shortcut,
    this.checked = false,
    this.destructive = false,
    this.disabled = false,
    this.disabledReason,
    this.onSelect,
  });

  final String id;
  final String label;
  final Widget? icon;
  final List<String>? shortcut;
  final bool checked;
  final bool destructive;
  final bool disabled;
  final String? disabledReason;
  final VoidCallback? onSelect;
}

/// Grouped items with an optional section label.
final class AppMenuSection extends AppMenuEntry {
  const AppMenuSection({this.label, required this.items});

  final String? label;
  final List<AppMenuItem> items;
}

/// Horizontal rule between menu groups.
final class AppMenuSeparator extends AppMenuEntry {
  const AppMenuSeparator();
}

// ---------------------------------------------------------------------------
// Dropdown menu (web `Menu`)
// ---------------------------------------------------------------------------

/// Dropdown menu aligned to a trigger (web `Menu` → `DropdownMenu`).
class AppMenu extends StatefulWidget {
  const AppMenu({
    required this.trigger,
    required this.entries,
    this.align = AppPopoverAlign.start,
    this.open,
    this.onOpenChange,
    super.key,
  });

  final Widget trigger;
  final List<AppMenuEntry> entries;
  final AppPopoverAlign align;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> {
  VoidCallback? _closeMenu;

  void _handleItemSelected(AppMenuItem item) {
    item.onSelect?.call();
    _closeMenu?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopover(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      align: widget.align,
      matchTriggerWidth: false,
      minWidth: _kMenuMinWidth,
      triggerBuilder: (context, isOpen, toggle) {
        _closeMenu = isOpen ? toggle : null;
        return _AppMenuTrigger(isOpen: isOpen, onToggle: toggle, child: widget.trigger);
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space1),
        child: _AppMenuList(entries: widget.entries, onItemSelected: _handleItemSelected),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context menu (web `ContextMenu`)
// ---------------------------------------------------------------------------

/// Right-click / long-press menu (web `ContextMenu` → Radix context menu).
class AppContextMenu extends StatefulWidget {
  const AppContextMenu({required this.child, required this.entries, super.key});

  final Widget child;
  final List<AppMenuEntry> entries;

  @override
  State<AppContextMenu> createState() => _AppContextMenuState();
}

class _AppContextMenuState extends State<AppContextMenu> with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late final AnimationController _controller;

  Offset _anchorGlobal = Offset.zero;
  var _isOpen = false;
  var _isClosing = false;
  var _overlayRefreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.fadeScale));
  }

  @override
  void didUpdateWidget(covariant AppContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isOpen && widget.entries != oldWidget.entries) {
      _scheduleOverlayRefresh();
    }
  }

  void _scheduleOverlayRefresh() {
    if (_overlayRefreshScheduled || _isClosing) return;
    _overlayRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayRefreshScheduled = false;
      if (!mounted || !_isOpen || _isClosing) return;
      final entry = _overlayEntry;
      if (entry == null || !entry.mounted) return;
      entry.markNeedsBuild();
    });
  }

  Offset _anchorInOverlay(BuildContext overlayContext) {
    final overlayBox = Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.attached) return _anchorGlobal;
    return overlayBox.globalToLocal(_anchorGlobal);
  }

  @override
  void dispose() {
    _removeOverlay(immediate: true);
    _controller.dispose();
    super.dispose();
  }

  void _openAt(Offset globalPosition) {
    if (_isOpen) {
      _close(immediate: true);
    }
    _anchorGlobal = globalPosition;
    setState(() => _isOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      _showOverlay();
      _controller.forward(from: 0);
    });
  }

  void _close({bool immediate = false}) {
    if (!_isOpen) return;
    _overlayRefreshScheduled = false;
    _isClosing = true;
    setState(() => _isOpen = false);

    if (immediate) {
      _isClosing = false;
      _removeOverlay(immediate: true);
      return;
    }

    _controller.reverse().whenComplete(() {
      _isClosing = false;
      if (!_isOpen) {
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      final entry = _overlayEntry;
      if (entry == null || !entry.mounted) return;
      entry.markNeedsBuild();
    });
  }

  void _removeOverlay({bool immediate = false}) {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry.remove();
    if (immediate) {
      _controller.value = 0;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kSecondaryMouseButton) return;
    _openAt(event.position);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _openAt(details.globalPosition);
  }

  void _handleItemSelected(AppMenuItem item) {
    item.onSelect?.call();
    _close();
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (overlayContext) {
        final anchor = _anchorInOverlay(overlayContext);

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _close()),
                ),
                Positioned(
                  left: anchor.dx,
                  top: anchor.dy,
                  child: IntrinsicWidth(
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                          _close();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AppMotion.animatedPreset(
                        context: overlayContext,
                        preset: AppMotionPreset.fadeScale,
                        animation: _controller,
                        child: _AppMenuSurface(
                          minWidth: _kMenuMinWidth,
                          child: _AppMenuList(entries: widget.entries, onItemSelected: _handleItemSelected),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      child: Listener(onPointerDown: _handlePointerDown, child: widget.child),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared internals
// ---------------------------------------------------------------------------

class _AppMenuTrigger extends StatelessWidget {
  const _AppMenuTrigger({required this.isOpen, required this.onToggle, required this.child});

  final bool isOpen;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: isOpen,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onToggle, child: child),
    );
  }
}

class _AppMenuSurface extends StatelessWidget {
  const _AppMenuSurface({required this.child, this.minWidth});

  final Widget child;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        decoration: elevation.decoration(
          level: 2,
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(AppSpacing.space1), child: child),
      ),
    );
  }
}

class _AppMenuList extends StatelessWidget {
  const _AppMenuList({required this.entries, required this.onItemSelected});

  final List<AppMenuEntry> entries;
  final ValueChanged<AppMenuItem> onItemSelected;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      switch (entry) {
        case AppMenuSeparator():
          children.add(const _AppMenuSeparatorRow());
        case AppMenuSection(:final label, :final items):
          if (label != null) {
            children.add(_AppMenuSectionLabel(label: label));
          }
          for (final item in items) {
            children.add(_AppMenuItemRow(item: item, onSelected: () => onItemSelected(item)));
          }
        case AppMenuItem item:
          children.add(_AppMenuItemRow(item: item, onSelected: () => onItemSelected(item)));
      }
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _AppMenuSectionLabel extends StatelessWidget {
  const _AppMenuSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space2),
      child: Text(label, style: AppTypography.overline(context).copyWith(color: context.appColors.textTertiary)),
    );
  }
}

class _AppMenuSeparatorRow extends StatelessWidget {
  const _AppMenuSeparatorRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
      child: SizedBox(height: 1, child: ColoredBox(color: context.appColors.borderSubtle)),
    );
  }
}

class _AppMenuItemRow extends StatefulWidget {
  const _AppMenuItemRow({required this.item, required this.onSelected});

  final AppMenuItem item;
  final VoidCallback onSelected;

  @override
  State<_AppMenuItemRow> createState() => _AppMenuItemRowState();
}

class _AppMenuItemRowState extends State<_AppMenuItemRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warningColor = isDark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber700;
    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;

    final foreground = item.disabled
        ? colors.textDisabled
        : (item.destructive ? colors.statusDangerFg : colors.textPrimary);

    Color background = Colors.transparent;
    if (!item.disabled && _hovered) {
      background = item.destructive ? dangerSurface : colors.surfaceHover;
    }

    final semanticsLabel = item.disabled && item.disabledReason != null
        ? '${item.label}. ${item.disabledReason}'
        : item.label;

    return Semantics(
      button: true,
      enabled: !item.disabled,
      label: semanticsLabel,
      checked: item.checked,
      child: MouseRegion(
        onEnter: item.disabled ? null : (_) => setState(() => _hovered = true),
        onExit: item.disabled ? null : (_) => setState(() => _hovered = false),
        cursor: item.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: item.disabled ? null : widget.onSelected,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 6),
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    IconTheme(
                      data: IconThemeData(size: 16, color: item.disabled ? colors.textDisabled : colors.iconDefault),
                      child: item.icon!,
                    ),
                    const SizedBox(width: AppSpacing.space2),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: AppTypography.body(context).copyWith(color: foreground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.disabled && item.disabledReason != null)
                          Text(
                            item.disabledReason!,
                            style: AppTypography.caption(context).copyWith(color: warningColor),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (item.checked)
                    Icon(Icons.check, size: 16, color: colors.textLink)
                  else if (item.shortcut != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: AppSpacing.space2),
                      child: AppKbd(keys: item.shortcut),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
