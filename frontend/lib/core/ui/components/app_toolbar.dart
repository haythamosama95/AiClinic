import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Horizontal toolbar with start, center, and end slots (web `Toolbar`).
class AppToolbar extends StatelessWidget {
  const AppToolbar({
    this.start,
    this.center,
    this.end,
    this.sticky = false,
    super.key,
  });

  final Widget? start;
  final Widget? center;
  final Widget? end;
  final bool sticky;

  Widget _slot(Widget child) {
    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [child],
    );
  }

  Widget _buildSlots() {
    if (center != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (start != null) _slot(start!),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.center,
              child: center,
            ),
          ),
          if (end != null) _slot(end!),
        ],
      );
    }

    if (start == null && end != null) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: _slot(end!),
      );
    }

    if (start != null && end == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: _slot(start!),
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space2,
      children: [
        if (start != null) _slot(start!),
        if (end != null) _slot(end!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>()!;

    return Semantics(
      container: true,
      label: 'toolbar',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderDefault),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: sticky ? elevation.shadows1 : null,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: _buildSlots(),
        ),
      ),
    );
  }
}
