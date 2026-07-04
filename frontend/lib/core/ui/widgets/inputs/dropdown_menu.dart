import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Menu row with label, optional icon, and tap handler.
class AppDropdownMenuItem {
  const AppDropdownMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
}

/// Section heading inside a dropdown menu.
class AppDropdownMenuLabel extends StatelessWidget {
  const AppDropdownMenuLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1 + AppSpacing.s0_5,
      ),
      child: Text(
        label,
        style: context.typography.overline.copyWith(
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}

/// Horizontal rule between menu groups.
class AppDropdownMenuSeparator extends StatelessWidget {
  const AppDropdownMenuSeparator({super.key});

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

/// Union of supported dropdown menu children.
sealed class AppDropdownMenuEntry {}

class AppDropdownMenuItemEntry extends AppDropdownMenuEntry {
  AppDropdownMenuItemEntry(this.item);

  final AppDropdownMenuItem item;
}

class AppDropdownMenuLabelEntry extends AppDropdownMenuEntry {
  AppDropdownMenuLabelEntry(this.label);

  final String label;
}

class AppDropdownMenuSeparatorEntry extends AppDropdownMenuEntry {
  AppDropdownMenuSeparatorEntry();
}

/// Popover-based dropdown menu with fade-scale motion.
class AppDropdownMenu extends StatefulWidget {
  const AppDropdownMenu({
    super.key,
    required this.trigger,
    required this.items,
    this.open,
    this.onOpenChange,
    this.placement = const AppPopoverPlacement(align: AppPopoverAlign.start),
    this.minWidth = 160,
  });

  final Widget trigger;
  final List<AppDropdownMenuEntry> items;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;
  final AppPopoverPlacement placement;
  final double minWidth;

  /// Convenience constructor accepting [AppDropdownMenuItem] rows only.
  factory AppDropdownMenu.simple({
    Key? key,
    required Widget trigger,
    required List<AppDropdownMenuItem> items,
    bool? open,
    ValueChanged<bool>? onOpenChange,
    AppPopoverPlacement placement = const AppPopoverPlacement(
      align: AppPopoverAlign.start,
    ),
    double minWidth = 160,
  }) {
    return AppDropdownMenu(
      key: key,
      trigger: trigger,
      items: items.map(AppDropdownMenuItemEntry.new).toList(),
      open: open,
      onOpenChange: onOpenChange,
      placement: placement,
      minWidth: minWidth,
    );
  }

  @override
  State<AppDropdownMenu> createState() => _AppDropdownMenuState();
}

class _AppDropdownMenuState extends State<AppDropdownMenu> {
  @override
  Widget build(BuildContext context) {
    return AppPopover(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      placement: widget.placement,
      minWidth: widget.minWidth,
      trigger: widget.trigger,
      contentBuilder: (context, hide) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in widget.items)
                _buildEntry(context, entry, hide),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntry(
    BuildContext context,
    AppDropdownMenuEntry entry,
    VoidCallback hide,
  ) {
    return switch (entry) {
      AppDropdownMenuItemEntry(:final item) => _AppDropdownMenuItemTile(
        item: item,
        onSelected: () {
          hide();
          item.onTap?.call();
        },
      ),
      AppDropdownMenuLabelEntry(:final label) => AppDropdownMenuLabel(label),
      AppDropdownMenuSeparatorEntry() => const AppDropdownMenuSeparator(),
    };
  }
}

class _AppDropdownMenuItemTile extends StatefulWidget {
  const _AppDropdownMenuItemTile({
    required this.item,
    required this.onSelected,
  });

  final AppDropdownMenuItem item;
  final VoidCallback onSelected;

  @override
  State<_AppDropdownMenuItemTile> createState() =>
      _AppDropdownMenuItemTileState();
}

class _AppDropdownMenuItemTileState extends State<_AppDropdownMenuItemTile> {
  bool _hovered = false;
  bool _focused = false;

  bool get _highlighted => (_hovered || _focused) && widget.item.enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final item = widget.item;

    final foreground = !item.enabled
        ? colors.textDisabled
        : item.destructive
        ? colors.statusDangerFg
        : colors.textPrimary;

    final background = !_highlighted
        ? Colors.transparent
        : item.destructive
        ? colors.statusDangerSurface
        : colors.surfaceHover;

    return Semantics(
      button: true,
      enabled: item.enabled,
      label: item.label,
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: item.enabled ? widget.onSelected : null,
              borderRadius: AppRadius.mdAll,
              hoverColor: Colors.transparent,
              splashColor: colors.surfaceMuted.withValues(alpha: 0.4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s1 + AppSpacing.s0_5,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 16,
                        color: item.enabled
                            ? colors.iconDefault
                            : colors.textDisabled,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                    ],
                    Expanded(
                      child: Text(
                        item.label,
                        style: typography.body.copyWith(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
