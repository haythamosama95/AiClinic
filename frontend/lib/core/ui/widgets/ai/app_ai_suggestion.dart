import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Opt-in inline AI suggestion attached to a field or section.
class AppAiSuggestion extends StatefulWidget {
  const AppAiSuggestion({
    required this.message,
    this.onAccept,
    this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  State<AppAiSuggestion> createState() => _AppAiSuggestionState();
}

class _AppAiSuggestionState extends State<AppAiSuggestion> {
  bool _visible = true;

  void _handleDismiss() {
    if (!_visible) return;
    setState(() => _visible = false);
    final reduced = AppMotion.reduced(context);
    final duration = AppMotion.resolvePreset(
      AppMotionPreset.collapse,
      reduced: reduced,
      isExit: true,
    ).duration;
    Future<void>.delayed(duration, () {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppCollapse(
      expanded: _visible,
      child: AppFade(
        child: Semantics(
          container: true,
          label: 'AI suggestion',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAi,
              border: Border.all(color: colors.borderAi),
              borderRadius: AppRadii.lgAll,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: AppSpacing.s0_5,
                    ),
                    child: AppIcon(
                      icon: LucideIcons.sparkles,
                      size: AppIconSize.md,
                      color: colors.textAi,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.message,
                          style: typography.bodySm.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        if (widget.onAccept != null ||
                            widget.onDismiss != null) ...[
                          const SizedBox(height: AppSpacing.s2),
                          Wrap(
                            spacing: AppSpacing.s2,
                            runSpacing: AppSpacing.s2,
                            children: [
                              if (widget.onAccept != null)
                                AppButton(
                                  label: 'Use suggestion',
                                  variant: AppButtonVariant.ai,
                                  size: AppButtonSize.sm,
                                  onPressed: widget.onAccept,
                                ),
                              if (widget.onDismiss != null)
                                AppButton(
                                  label: 'Dismiss',
                                  variant: AppButtonVariant.ghost,
                                  size: AppButtonSize.sm,
                                  onPressed: _handleDismiss,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onDismiss != null) ...[
                    const SizedBox(width: AppSpacing.s2),
                    AppIconButton(
                      icon: LucideIcons.x,
                      semanticLabel: 'Dismiss suggestion',
                      size: AppIconButtonSize.sm,
                      variant: AppIconButtonVariant.ghost,
                      onPressed: _handleDismiss,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
