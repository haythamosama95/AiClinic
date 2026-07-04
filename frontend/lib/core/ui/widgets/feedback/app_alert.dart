import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Semantic tone for [AppAlert].
enum AppAlertVariant { info, success, warning, danger, ai }

/// Persistent contextual banner with optional actions and dismiss.
class AppAlert extends StatefulWidget {
  const AppAlert({
    required this.title,
    this.variant = AppAlertVariant.info,
    this.body,
    this.actions,
    this.dismissible = false,
    this.onDismiss,
    super.key,
  });

  final AppAlertVariant variant;
  final String title;
  final String? body;
  final List<Widget>? actions;
  final bool dismissible;
  final VoidCallback? onDismiss;

  @override
  State<AppAlert> createState() => _AppAlertState();
}

class _AppAlertState extends State<AppAlert> {
  bool _expanded = true;

  void _handleDismiss() {
    setState(() => _expanded = false);
    final reduced = AppMotion.reduced(context);
    final duration = AppMotion.resolvePreset(
      AppMotionPreset.collapse,
      reduced: reduced,
      isExit: true,
    ).duration;
    Future<void>.delayed(duration, () {
      if (!mounted) return;
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppCollapse(
      expanded: _expanded,
      child: _AlertContent(
        variant: widget.variant,
        title: widget.title,
        body: widget.body,
        actions: widget.actions,
        dismissible: widget.dismissible,
        onDismiss: _handleDismiss,
      ),
    );
  }
}

class _AlertContent extends StatelessWidget {
  const _AlertContent({
    required this.variant,
    required this.title,
    required this.body,
    required this.actions,
    required this.dismissible,
    required this.onDismiss,
  });

  final AppAlertVariant variant;
  final String title;
  final String? body;
  final List<Widget>? actions;
  final bool dismissible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final scheme = _resolveScheme(colors, variant);
    final isAlert = variant == AppAlertVariant.danger;

    return Semantics(
      container: true,
      liveRegion: isAlert,
      label: title,
      hint: body,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.background,
          border: Border.all(color: scheme.border),
          borderRadius: AppRadii.lgAll,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.s0_5),
                child: AppIcon(
                  icon: _iconForVariant(variant),
                  size: AppIconSize.sm,
                  color: scheme.foreground,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: typography.bodyStrong.copyWith(
                        color: scheme.foreground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        body!,
                        style: typography.bodySm.copyWith(
                          color: scheme.foreground.withValues(alpha: 0.9),
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (actions != null && actions!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s3),
                      Wrap(
                        spacing: AppSpacing.s2,
                        runSpacing: AppSpacing.s2,
                        children: actions!,
                      ),
                    ],
                  ],
                ),
              ),
              if (dismissible) ...[
                const SizedBox(width: AppSpacing.s2),
                AppIconButton(
                  icon: LucideIcons.x,
                  semanticLabel: 'Dismiss alert',
                  size: AppIconButtonSize.sm,
                  variant: AppIconButtonVariant.ghost,
                  onPressed: onDismiss,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({Color background, Color foreground, Color border}) _resolveScheme(
  AppColors colors,
  AppAlertVariant variant,
) {
  return switch (variant) {
    AppAlertVariant.info => (
      background: colors.statusInfoSurface,
      foreground: colors.statusInfoFg,
      border: colors.statusInfoBorder,
    ),
    AppAlertVariant.success => (
      background: colors.statusSuccessSurface,
      foreground: colors.statusSuccessFg,
      border: colors.statusSuccessBorder,
    ),
    AppAlertVariant.warning => (
      background: colors.statusWarningSurface,
      foreground: colors.statusWarningFg,
      border: colors.statusWarningBorder,
    ),
    AppAlertVariant.danger => (
      background: colors.statusDangerSurface,
      foreground: colors.statusDangerFg,
      border: colors.statusDangerBorder,
    ),
    AppAlertVariant.ai => (
      background: colors.surfaceAi,
      foreground: colors.textAi,
      border: colors.borderAi,
    ),
  };
}

IconData _iconForVariant(AppAlertVariant variant) {
  return switch (variant) {
    AppAlertVariant.info => LucideIcons.info,
    AppAlertVariant.success => LucideIcons.checkCircle2,
    AppAlertVariant.warning => LucideIcons.alertCircle,
    AppAlertVariant.danger => LucideIcons.circleX,
    AppAlertVariant.ai => LucideIcons.sparkles,
  };
}
