import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Grouped settings container: title, divider, then controls.
///
/// When [onEdit] is set, the header shows an edit icon in view mode and
/// save/cancel actions on the same row while [isEditing] is true.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    required this.child,
    this.isEditing = false,
    this.isSaving = false,
    this.headerLeadingActions,
    this.onEdit,
    this.onSave,
    this.onCancel,
    super.key,
  });

  final String title;
  final Widget child;
  final bool isEditing;
  final bool isSaving;

  /// Optional actions shown to the left of the edit icon in view mode.
  final Widget? headerLeadingActions;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final headerActions = _buildHeaderActions(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
                  ),
                ),
                if (headerActions != null) headerActions,
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Padding(padding: const EdgeInsets.all(SpacingTokens.lg), child: child),
        ],
      ),
    );
  }

  Widget? _buildHeaderActions(BuildContext context) {
    if (isEditing) {
      if (onSave == null || onCancel == null) {
        return null;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            expand: false,
            onPressed: isSaving ? null : onCancel,
          ),
          const SizedBox(width: SpacingTokens.sm),
          AppButton(label: 'Save', expand: false, isLoading: isSaving, onPressed: isSaving ? null : onSave),
        ],
      );
    }

    if (onEdit == null) {
      return null;
    }

    final colors = context.semanticColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (headerLeadingActions != null) ...[headerLeadingActions!, const SizedBox(width: SpacingTokens.sm)],
        IconButton(
          tooltip: 'Edit',
          onPressed: onEdit,
          icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
        ),
      ],
    );
  }
}

/// Lays out [SettingsField] widgets side by side, stacking on narrow widths.
class SettingsFieldsRow extends StatelessWidget {
  const SettingsFieldsRow({required this.children, this.compactBreakpoint = compactBreakpointDefault, super.key});

  static const compactBreakpointDefault = 480.0;

  final List<Widget> children;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: SpacingTokens.lg),
                children[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: SpacingTokens.lg),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Labeled setting row inside a [SettingsSectionCard].
class SettingsField extends StatelessWidget {
  const SettingsField({required this.label, required this.child, this.description, super.key});

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
        ),
        if (description != null) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(description!, style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
        ],
        const SizedBox(height: SpacingTokens.md),
        child,
      ],
    );
  }
}
