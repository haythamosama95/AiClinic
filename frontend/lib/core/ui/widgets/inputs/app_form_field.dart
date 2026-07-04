import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Standard label/control/helper/error scaffold for form fields.
class AppFormField extends StatelessWidget {
  const AppFormField({
    required this.label,
    required this.child,
    this.requiredMark = false,
    this.hint,
    this.helperText,
    this.error,
    this.controlId,
    super.key,
  });

  final String label;
  final Widget child;
  final bool requiredMark;
  final String? hint;
  final String? helperText;
  final String? error;
  final String? controlId;

  static const double _fieldGap = AppSpacing.s1 + AppSpacing.s0_5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final helperId = helperText != null ? '${controlId ?? label}-helper' : null;
    final errorId = error != null ? '${controlId ?? label}-error' : null;
    final describedBy = [
      if (error == null) helperId,
      if (error != null) errorId,
    ].whereType<String>().join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                label: requiredMark ? '$label (required)' : label,
                child: Text(
                  label,
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (requiredMark) ...[
              const SizedBox(width: AppSpacing.s0_5),
              Text(
                '*',
                style: typography.bodyStrong.copyWith(color: colors.statusDangerFg),
                semanticsLabel: 'required',
              ),
            ],
            if (hint != null) ...[
              const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
              Tooltip(
                message: hint!,
                child: AppPressable(
                  onTap: () {},
                  semanticLabel: 'More about $label',
                  borderRadius: AppRadii.smAll,
                  child: AppIcon(
                    icon: LucideIcons.circleHelp,
                    size: AppIconSize.sm,
                    color: colors.iconMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: _fieldGap),
        Semantics(
          label: describedBy.isEmpty ? null : describedBy,
          hint: describedBy.isEmpty ? null : describedBy,
          textField: true,
          child: child,
        ),
        if (error != null) ...[
          const SizedBox(height: _fieldGap),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sPx),
                  child: AppIcon(
                    icon: LucideIcons.circleAlert,
                    size: AppIconSize.sm,
                    color: colors.statusDangerFg,
                  ),
                ),
                const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
                Expanded(
                  child: Text(
                    error!,
                    style: typography.caption.copyWith(
                      color: colors.statusDangerFg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: _fieldGap),
          Text(
            helperText!,
            style: typography.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}
