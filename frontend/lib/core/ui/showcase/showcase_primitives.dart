import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Shared layout primitives for component showcase sections.
class ShowcaseSection extends StatelessWidget {
  const ShowcaseSection({
    super.key,
    required this.title,
    this.description,
    required this.child,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: typography.h3.copyWith(color: colors.textPrimary)),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Text(
            description!,
            style: typography.body.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}

class ShowcaseDemoGrid extends StatelessWidget {
  const ShowcaseDemoGrid({
    super.key,
    required this.children,
    this.minWidth = 160,
  });

  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: AppSpacing.s4,
          runSpacing: AppSpacing.s4,
          children: children,
        );
      },
    );
  }
}

class ShowcaseDemo extends StatelessWidget {
  const ShowcaseDemo({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: typography.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s2),
        child,
      ],
    );
  }
}

class ShowcaseGroupHeader extends StatelessWidget {
  const ShowcaseGroupHeader({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: typography.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              description,
              style: typography.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
