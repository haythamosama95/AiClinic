import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_nav.dart';
import 'package:ai_clinic/core/ui/layout/page_header.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Scaffolded placeholder for shell nav routes — mirrors web `PlaceholderPage`.
class ShellPlaceholderPage extends StatelessWidget {
  const ShellPlaceholderPage({
    required this.navId,
    super.key,
    this.title,
    this.description,
  });

  final String navId;
  final String? title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final meta = shellMetaForNavId(navId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: title ?? meta.title,
          description: description ?? meta.description,
        ),
        const SizedBox(height: AppSpacing.s8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.xlAll,
            border: Border.all(
              color: colors.borderDefault,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            color: colors.surfaceDefault,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: Center(
              child: Column(
                children: [
                  Text(
                    'Coming soon',
                    style: typography.bodyLg.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 448),
                    child: Text(
                      'This area is scaffolded for the application shell. '
                      'Feature content will land here in a future milestone.',
                      textAlign: TextAlign.center,
                      style: typography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 640 ? 3 : 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s4,
              children: [
                GridView.count(
                  crossAxisCount: crossCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.s4,
                  crossAxisSpacing: AppSpacing.s4,
                  childAspectRatio: 2.4,
                  children: List.generate(
                    3,
                    (_) => _StaticPlaceholderBlock(height: 96, colors: colors),
                  ),
                ),
                _StaticPlaceholderBlock(height: 192, colors: colors),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StaticPlaceholderBlock extends StatelessWidget {
  const _StaticPlaceholderBlock({required this.height, required this.colors});

  final double height;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.lgAll,
      ),
      child: SizedBox(height: height),
    );
  }
}
