import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Accessibility props to associate a control with [AppFormField].
@immutable
class AppFieldControlProps {
  const AppFieldControlProps({
    required this.id,
    this.invalid = false,
    this.describedBy,
  });

  final String id;
  final bool invalid;
  final String? describedBy;
}

/// Builds control association props (web `fieldControlProps` equivalent).
AppFieldControlProps fieldControlProps(
  String id, {
  bool invalid = false,
  String? describedBy,
}) {
  return AppFieldControlProps(
    id: id,
    invalid: invalid,
    describedBy: describedBy,
  );
}

/// Standard label / control / description / error scaffold for form fields.
class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    required this.id,
    required this.label,
    required this.child,
    this.required = false,
    this.description,
    this.error,
    this.controlProps,
  });

  final String id;
  final String label;
  final Widget child;
  final bool required;
  final String? description;
  final String? error;
  final AppFieldControlProps? controlProps;

  String? get _descriptionId =>
      description != null && error == null ? '$id-description' : null;

  String? get _errorId => error != null ? '$id-error' : null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final props =
        controlProps ??
        fieldControlProps(
          id,
          invalid: error != null,
          describedBy:
              [
                _descriptionId,
                _errorId,
              ].whereType<String>().join(' ').trim().isEmpty
              ? null
              : [_descriptionId, _errorId].whereType<String>().join(' '),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FormFieldLabel(label: label, required: required),
        const SizedBox(height: AppSpacing.s1 + AppSpacing.s0_5),
        Semantics(
          container: true,
          identifier: props.id,
          label: props.invalid && error != null ? '$label. $error' : label,
          hint: description,
          child: child,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s1 + AppSpacing.s0_5),
          Semantics(
            liveRegion: true,
            container: true,
            identifier: _errorId,
            label: error,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: colors.statusDangerFg,
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
        ] else if (description != null) ...[
          const SizedBox(height: AppSpacing.s1 + AppSpacing.s0_5),
          Semantics(
            container: true,
            identifier: _descriptionId,
            label: description,
            child: Text(
              description!,
              style: typography.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

class _FormFieldLabel extends StatelessWidget {
  const _FormFieldLabel({required this.label, required this.required});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Semantics(
      label: required ? '$label, required' : label,
      child: MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: typography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            if (required)
              Text(
                ' *',
                style: typography.bodyStrong.copyWith(
                  color: colors.statusDangerFg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
