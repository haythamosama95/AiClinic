import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Breakpoint matching web `lg` (1024px).
const _lgBreakpoint = 1024.0;

/// Settings section metadata mirroring web `SETTINGS_SCREENS`.
class _SettingsNavItem {
  const _SettingsNavItem({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;
}

const _settingsNavItems = <_SettingsNavItem>[
  _SettingsNavItem(id: 'general', label: 'General', icon: Icons.business),
  _SettingsNavItem(id: 'branches', label: 'Branches', icon: Icons.location_on),
  _SettingsNavItem(id: 'staff', label: 'Staff', icon: Icons.group),
  _SettingsNavItem(id: 'services', label: 'Services', icon: Icons.medical_services),
  _SettingsNavItem(id: 'notifications', label: 'Notifications', icon: Icons.notifications),
];

/// Left settings navigation rail (web `SettingsPage` `<nav>` + `settingsNavItemClass`).
class SettingsNavRail extends StatelessWidget {
  const SettingsNavRail({required this.active, required this.onNavigate, this.isItemEnabled, super.key});

  final String active;
  final ValueChanged<String> onNavigate;
  final bool Function(String itemId)? isItemEnabled;

  @override
  Widget build(BuildContext context) {
    final isVertical = MediaQuery.sizeOf(context).width >= _lgBreakpoint;
    final items = [
      for (final item in _settingsNavItems)
        _SettingsNavRailItem(
          item: item,
          active: active == item.id,
          enabled: isItemEnabled?.call(item.id) ?? true,
          isVertical: isVertical,
          onNavigate: onNavigate,
        ),
    ];

    return Semantics(
      label: 'Settings sections',
      container: true,
      child: isVertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.space1),
                  items[i],
                ],
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space1),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.space1),
                      items[i],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _SettingsNavRailItem extends StatefulWidget {
  const _SettingsNavRailItem({
    required this.item,
    required this.active,
    required this.enabled,
    required this.isVertical,
    required this.onNavigate,
  });

  final _SettingsNavItem item;
  final bool active;
  final bool enabled;
  final bool isVertical;
  final ValueChanged<String> onNavigate;

  @override
  State<_SettingsNavRailItem> createState() => _SettingsNavRailItemState();
}

class _SettingsNavRailItemState extends State<_SettingsNavRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = widget.active;
    final enabled = widget.enabled;
    final iconColor = !enabled
        ? colors.iconMuted.withValues(alpha: 0.45)
        : active
        ? colors.actionPrimary
        : colors.iconMuted;
    final textColor = !enabled
        ? colors.textTertiary
        : active
        ? colors.textPrimary
        : (_hovered ? colors.textPrimary : colors.textSecondary);
    final textStyle = AppTypography.body(
      context,
    ).copyWith(color: textColor, fontWeight: active ? FontWeight.w500 : FontWeight.w400);

    final content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.space3, vertical: 10),
      child: Row(
        mainAxisSize: widget.isVertical ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(widget.item.icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.space3),
          if (widget.isVertical)
            Expanded(child: Text(widget.item.label, style: textStyle))
          else
            Text(widget.item.label, style: textStyle),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      child: MouseRegion(
        onEnter: active || !enabled ? null : (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Material(
          color: active && enabled ? colors.surfaceSelected : (_hovered ? colors.surfaceHover : Colors.transparent),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: GestureDetector(
            onTap: enabled ? () => widget.onNavigate(widget.item.id) : null,
            behavior: HitTestBehavior.opaque,
            child: content,
          ),
        ),
      ),
    );
  }
}
