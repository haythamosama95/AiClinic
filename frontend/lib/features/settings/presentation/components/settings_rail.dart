import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_screen.dart';

/// Vertical navigation rail for personal settings (web `SettingsRail`).
class SettingsRail extends StatelessWidget {
  const SettingsRail({required this.activeScreenId, required this.onNavigate, super.key});

  final String activeScreenId;
  final ValueChanged<String> onNavigate;

  static const _railWidth = 248.0;
  static const _breakpoint = 768.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isWide = MediaQuery.sizeOf(context).width >= _breakpoint;

    final nav = Semantics(
      label: 'Settings sections',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isWide)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space2),
              child: Text(
                'SECTIONS',
                style: AppTypography.caption(context).copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  color: colors.textTertiary,
                ),
              ),
            ),
          if (isWide)
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceDefault,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space1 + AppSpacing.space05),
                child: _RailList(
                  activeScreenId: activeScreenId,
                  onNavigate: onNavigate,
                  horizontal: false,
                ),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceDefault,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _RailList(
                    activeScreenId: activeScreenId,
                    onNavigate: onNavigate,
                    horizontal: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!isWide) {
      return nav;
    }

    return SizedBox(width: _railWidth, child: Padding(padding: const EdgeInsetsDirectional.only(end: AppSpacing.space6), child: nav));
  }
}

class _RailList extends StatelessWidget {
  const _RailList({required this.activeScreenId, required this.onNavigate, required this.horizontal});

  final String activeScreenId;
  final ValueChanged<String> onNavigate;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final screen in SettingsScreens.all)
        _SettingsRailButton(
          screen: screen,
          active: screen.id == activeScreenId,
          horizontal: horizontal,
          onPressed: () => onNavigate(SettingsScreens.routeFor(screen.id)),
        ),
    ];

    if (horizontal) {
      return Row(mainAxisSize: MainAxisSize.min, spacing: AppSpacing.space1 + AppSpacing.space05, children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.space05,
      children: children,
    );
  }
}

class _SettingsRailButton extends StatefulWidget {
  const _SettingsRailButton({
    required this.screen,
    required this.active,
    required this.horizontal,
    required this.onPressed,
  });

  final SettingsScreenDefinition screen;
  final bool active;
  final bool horizontal;
  final VoidCallback onPressed;

  @override
  State<_SettingsRailButton> createState() => _SettingsRailButtonState();
}

class _SettingsRailButtonState extends State<_SettingsRailButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = widget.active;

    final background = active
        ? colors.surfaceSelected
        : (_hovered ? colors.surfaceMuted : Colors.transparent);
    final foreground = active || _hovered ? colors.textPrimary : colors.textSecondary;
    final iconColor = active ? colors.textLink : foreground.withValues(alpha: 0.7);

    return Semantics(
      button: true,
      selected: active,
      label: widget.screen.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.lg - 2),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(AppRadius.lg - 2),
            child: Stack(
              children: [
                if (active && !widget.horizontal)
                  PositionedDirectional(
                    start: 0,
                    top: AppSpacing.space1 + AppSpacing.space05,
                    bottom: AppSpacing.space1 + AppSpacing.space05,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(1)),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.horizontal ? AppSpacing.space3 + AppSpacing.space05 : AppSpacing.space3,
                    vertical: widget.horizontal ? AppSpacing.space2 : AppSpacing.space2 + AppSpacing.space05,
                  ),
                  child: Row(
                    mainAxisSize: widget.horizontal ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      Icon(widget.screen.icon, size: 16, color: iconColor),
                      const SizedBox(width: AppSpacing.space2 + AppSpacing.space05),
                      Text(
                        widget.screen.label,
                        style: AppTypography.bodySm(context).copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
