import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_skeletonizer_zone.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Scaffolded placeholder for routes awaiting feature UI (web `PlaceholderPage`).
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, this.description, this.breadcrumb, this.actions, super.key});

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(title: title, description: description, breadcrumb: breadcrumb, actions: actions),
        const SizedBox(height: AppSpacing.space8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Coming soon', style: AppTypography.bodyLg(context).copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      'This area is scaffolded for the application shell. Feature content will land here in a future milestone.',
                      style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppSkeletonizerZone(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;
                  Bone cardBone() => Bone(height: 96, borderRadius: BorderRadius.circular(AppRadius.md));
                  if (isWide) {
                    return Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.space4),
                          Expanded(child: cardBone()),
                        ],
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(height: AppSpacing.space4), cardBone()],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.space4),
              Bone(height: 192, borderRadius: BorderRadius.circular(AppRadius.md)),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: body);
        }
        return body;
      },
    );
  }
}
