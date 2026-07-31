import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_tooltip.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Label + helper/error wrapper for form controls (web `FormField`).
class AppFormField extends StatelessWidget {
  const AppFormField({
    required this.id,
    required this.label,
    required this.child,
    this.requiredMark = false,
    this.hint,
    this.helperText,
    this.error,
    super.key,
  });

  final String id;
  final String label;
  final bool requiredMark;
  final String? hint;
  final String? helperText;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppTypography.bodyStrong(context)),
            if (requiredMark) ...[
              const SizedBox(width: 2),
              Text('*', style: AppTypography.bodyStrong(context).copyWith(color: colors.statusDangerFg)),
              Semantics(label: '(required)', child: const SizedBox.shrink()),
            ],
            if (hint != null) ...[
              const SizedBox(width: AppSpacing.space2),
              AppTooltip(
                message: hint!,
                preferBelow: false,
                child: Semantics(
                  button: true,
                  label: 'More about $label',
                  child: IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.help_outline, size: 16, color: colors.iconMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 20, height: 20),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        Semantics(
          container: true,
          textField: true,
          explicitChildNodes: true,
          label: label,
          hint: helperText,
          value: error,
          child: child,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.error_outline, size: 16, color: colors.statusDangerFg),
                ),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(error!, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
                ),
              ],
            ),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(helperText!, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
        ],
      ],
    );
  }
}

/// Props to wire a control to its parent [AppFormField].
AppFormFieldControlProps fieldControlProps(String id, {bool invalid = false, String? describedBy}) {
  return AppFormFieldControlProps(id: id, invalid: invalid, describedBy: describedBy);
}

class AppFormFieldControlProps {
  const AppFormFieldControlProps({required this.id, this.invalid = false, this.describedBy});

  final String id;
  final bool invalid;
  final String? describedBy;
}
