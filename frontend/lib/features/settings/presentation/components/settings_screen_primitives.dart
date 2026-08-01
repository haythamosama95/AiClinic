import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Screen body with header and panel stacked (web `space-y-6`).
class SettingsScreenScaffold extends StatelessWidget {
  const SettingsScreenScaffold({required this.header, required this.panel, super.key});

  final Widget header;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.space6,
      children: [header, panel],
    );
  }
}

/// Screen-level header with icon tile (web `ScreenHeader`).
class SettingsScreenHeader extends StatelessWidget {
  const SettingsScreenHeader({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final leading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            border: Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Icon(icon, size: 20, color: colors.textLink),
        ),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                description,
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    if (action == null) {
      return leading;
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: AppSpacing.space4,
      runSpacing: AppSpacing.space4,
      alignment: WrapAlignment.spaceBetween,
      children: [leading, action!],
    );
  }
}

/// Bordered content panel (web `ContentPanel`).
class SettingsContentPanel extends StatelessWidget {
  const SettingsContentPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: elevation.shadows1,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: child,
      ),
    );
  }
}

/// Label + control row (web `SettingRow`).
class SettingsSettingRow extends StatelessWidget {
  const SettingsSettingRow({required this.title, required this.control, this.description, super.key});

  final String title;
  final String? description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space3,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.space1),
                  Text(description!, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
                ],
              ],
            ),
          ),
          control,
        ],
      ),
    );
  }
}

/// Divides setting rows inside a panel.
class SettingsDividedRows extends StatelessWidget {
  const SettingsDividedRows({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rows = <Widget>[];

    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: colors.borderSubtle));
      }
      rows.add(children[index]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
