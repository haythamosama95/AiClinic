import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Visual variant for [AppAlert] (web `AlertVariant`).
enum AppAlertVariant { info, success, warning, danger, ai }

/// Inline status banner (web `Alert`).
class AppAlert extends StatefulWidget {
  const AppAlert({
    required this.title,
    this.variant = AppAlertVariant.info,
    this.child,
    this.actions,
    this.dismissible = false,
    this.onDismiss,
    super.key,
  });

  final AppAlertVariant variant;
  final String title;
  final Widget? child;
  final Widget? actions;
  final bool dismissible;
  final VoidCallback? onDismiss;

  @override
  State<AppAlert> createState() => _AppAlertState();
}

class _AppAlertState extends State<AppAlert> {
  var _visible = true;

  void _handleDismiss() {
    widget.onDismiss?.call();
    if (mounted) {
      setState(() => _visible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final colors = context.appColors;
    final palette = _AlertPalette.resolve(colors, widget.variant);
    final icon = _iconFor(widget.variant);

    return Semantics(
      role: widget.variant == AppAlertVariant.danger ? SemanticsRole.alert : SemanticsRole.status,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16, color: palette.foreground),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.bodyStrong(context).copyWith(color: palette.foreground),
                    ),
                    if (widget.child != null) ...[
                      const SizedBox(height: AppSpacing.space1),
                      DefaultTextStyle(
                        style: AppTypography.bodySm(context).copyWith(
                          color: palette.foreground.withValues(alpha: 0.9),
                        ),
                        child: widget.child!,
                      ),
                    ],
                    if (widget.actions != null) ...[
                      const SizedBox(height: AppSpacing.space3),
                      widget.actions!,
                    ],
                  ],
                ),
              ),
              if (widget.dismissible)
                AppIconButton(
                  icon: const Icon(Icons.close),
                  label: 'Dismiss alert',
                  variant: AppIconButtonVariant.ghost,
                  size: AppIconButtonSize.sm,
                  onPressed: _handleDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(AppAlertVariant variant) => switch (variant) {
    AppAlertVariant.info => Icons.info_outline,
    AppAlertVariant.success => Icons.check_circle_outlined,
    AppAlertVariant.warning => Icons.error_outline,
    AppAlertVariant.danger => Icons.cancel_outlined,
    AppAlertVariant.ai => Icons.auto_awesome_outlined,
  };
}

class _AlertPalette {
  const _AlertPalette({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  static _AlertPalette resolve(AppSemanticColors colors, AppAlertVariant variant) {
    return switch (variant) {
      AppAlertVariant.info => _AlertPalette(
        background: colors.statusInfoSurface,
        foreground: colors.statusInfoFg,
        border: colors.statusInfoBorder,
      ),
      AppAlertVariant.success => _AlertPalette(
        background: colors.statusSuccessSurface,
        foreground: colors.statusSuccessFg,
        border: colors.statusSuccessBorder,
      ),
      AppAlertVariant.warning => _AlertPalette(
        background: colors.statusWarningSurface,
        foreground: colors.statusWarningFg,
        border: colors.statusWarningBorder,
      ),
      AppAlertVariant.danger => _AlertPalette(
        background: colors.statusDangerSurface,
        foreground: colors.statusDangerFg,
        border: colors.statusDangerBorder,
      ),
      AppAlertVariant.ai => _AlertPalette(
        background: colors.surfaceAi,
        foreground: colors.textAi,
        border: colors.borderAi,
      ),
    };
  }
}
