import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/display/kbd.dart';
import 'package:ai_clinic/core/ui/widgets/display/tooltip.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Menu row definition matching web `MenuItemDef`.
@immutable
class MenuItemDef {
  const MenuItemDef({
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

/// Grouped section inside a menu.
@immutable
class MenuSection {
  const MenuSection({
    this.label,
    required this.items,
  });

  final String? label;
  final List<MenuItemDef> items;
}

/// Visual separator between menu groups.
@immutable
class MenuSeparator {
  const MenuSeparator();
}

/// Union of menu content entries.
sealed class MenuEntry {}

class MenuItemEntry extends MenuEntry {
  MenuItemEntry(this.item);

  final MenuItemDef item;
}

class MenuSectionEntry extends MenuEntry {
  MenuSectionEntry(this.section);

  final MenuSection section;
}

class MenuSeparatorEntry extends MenuEntry {
  MenuSeparatorEntry();
}

/// Dropdown menu triggered by [trigger] with sections, shortcuts, and checks.
class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.trigger,
    required this.entries,
    this.align = AppPopoverAlign.start,
    this.open,
    this.onOpenChange,
  });

  final Widget trigger;
  final List<MenuEntry> entries;
  final AppPopoverAlign align;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;

  @override
  Widget build(BuildContext context) {
    return AppPopover(
      open: open,
      onOpenChange: onOpenChange,
      placement: AppPopoverPlacement(align: align),
      minWidth: 192,
      trigger: trigger,
      contentBuilder: (context, hide) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                _MenuEntryWidget(
                  entry: entry,
                  onSelected: hide,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Right-click context menu for [child].
class AppContextMenu extends ConsumerStatefulWidget {
  const AppContextMenu({
    super.key,
    required this.child,
    required this.entries,
  });

  final Widget child;
  final List<MenuEntry> entries;

  @override
  ConsumerState<AppContextMenu> createState() => _AppContextMenuState();
}

class _AppContextMenuState extends ConsumerState<AppContextMenu> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _hide() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _show(Offset globalPosition) {
    _hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    final reducedMotion = AppMotion.isReducedMotion(context);
    final transition = AppMotion.resolveTransition(
      preset: AppMotionPreset.fadeScale,
      reducedMotion: reducedMotion,
    );

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: transition.duration,
                curve: transition.curve,
                builder: (context, t, child) {
                  final hidden = AppMotion.hiddenValues(AppMotionPreset.fadeScale, direction: Directionality.of(context));
                  final visible = AppMotion.visibleValues;
                  final values = hidden.lerp(visible, t);
                  return Opacity(
                    opacity: values.opacity,
                    child: Transform.scale(
                      scale: values.scale,
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: overlayContext.colors.surfaceRaised,
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(color: overlayContext.colors.borderDefault),
                      boxShadow: overlayContext.elevation.level2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s1),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in widget.entries)
                            _MenuEntryWidget(
                              entry: entry,
                              onSelected: _hide,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _show(details.globalPosition),
      child: widget.child,
    );
  }
}

class _MenuEntryWidget extends StatelessWidget {
  const _MenuEntryWidget({
    required this.entry,
    required this.onSelected,
  });

  final MenuEntry entry;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return switch (entry) {
      MenuSeparatorEntry() => const _MenuSeparator(),
      MenuSectionEntry(:final section) => _MenuSection(
        section: section,
        onSelected: onSelected,
      ),
      MenuItemEntry(:final item) => _MenuItemTile(
        item: item,
        onSelected: () {
          onSelected();
          item.onSelect?.call();
        },
      ),
    };
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({
    required this.section,
    required this.onSelected,
  });

  final MenuSection section;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (section.label != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s1 + AppSpacing.s0_5,
            ),
            child: Text(
              section.label!,
              style: context.typography.overline.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
        for (final item in section.items)
          _MenuItemTile(
            item: item,
            onSelected: () {
              onSelected();
              item.onSelect?.call();
            },
          ),
      ],
    );
  }
}

class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
      child: Divider(
        height: 1,
        thickness: 1,
        color: context.colors.borderSubtle,
      ),
    );
  }
}

class _MenuItemTile extends ConsumerStatefulWidget {
  const _MenuItemTile({
    required this.item,
    required this.onSelected,
  });

  final MenuItemDef item;
  final VoidCallback onSelected;

  @override
  ConsumerState<_MenuItemTile> createState() => _MenuItemTileState();
}

class _MenuItemTileState extends ConsumerState<_MenuItemTile> {
  bool _hovered = false;
  bool _focused = false;

  bool get _highlighted => (_hovered || _focused) && !widget.item.disabled;

  double get _verticalPadding {
    return switch (ref.watch(appDensityProvider)) {
      AppDensity.compact => AppSpacing.s1,
      AppDensity.default_ => AppSpacing.s1 + AppSpacing.s0_5,
      AppDensity.comfortable => AppSpacing.s2,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    final foreground = item.disabled
        ? colors.textDisabled
        : item.destructive
        ? colors.statusDangerFg
        : colors.textPrimary;

    final background = !_highlighted
        ? Colors.transparent
        : item.destructive
        ? colors.statusDangerSurface
        : colors.surfaceHover;

    Widget content = Row(
      children: [
        if (item.icon != null) ...[
          DefaultTextStyle(
            style: TextStyle(color: !item.disabled ? colors.iconDefault : colors.textDisabled),
            child: item.icon!,
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
        Expanded(
          child: Text(
            item.label,
            style: context.typography.body.copyWith(color: foreground),
          ),
        ),
        if (item.checked)
          Icon(Icons.check, size: 16, color: colors.textLink)
        else if (item.shortcut != null)
          AppKbd(keys: item.shortcut),
      ],
    );

    if (item.disabled && item.disabledReason != null) {
      content = AppTooltip(
        message: Text(item.disabledReason!),
        child: content,
      );
    }

    return Semantics(
      button: true,
      enabled: !item.disabled,
      label: item.label,
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: MouseRegion(
          onEnter: item.disabled ? null : (_) => setState(() => _hovered = true),
          onExit: item.disabled ? null : (_) => setState(() => _hovered = false),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: item.disabled ? null : widget.onSelected,
              borderRadius: AppRadius.mdAll,
              hoverColor: Colors.transparent,
              splashColor: colors.surfaceMuted.withValues(alpha: 0.4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: _verticalPadding,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: AppRadius.mdAll,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
