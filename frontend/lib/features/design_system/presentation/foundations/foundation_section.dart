import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'dev_section_registry.dart';

/// Reusable foundation section wrapper matching web `Section`.
class FoundationSection extends StatelessWidget {
  const FoundationSection({
    required this.id,
    required this.title,
    required this.child,
    this.description,
    super.key,
  });

  final String id;
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return KeyedSubtree(
      key: DevSectionRegistry.keyFor(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.h2(context)),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      description!,
                      style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          child,
        ],
      ),
    );
  }
}
