import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Tab-level title and single-line description with trailing actions.
class ClinicTabHeader extends StatelessWidget {
  const ClinicTabHeader({required this.title, required this.description, this.actions, super.key});

  final String title;
  final String description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTypography.h3(context)),
              const SizedBox(height: AppSpacing.space1),
              Text(description, style: AppTypography.bodySm(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (actions != null) ...[const SizedBox(width: AppSpacing.space4), actions!],
      ],
    );
  }
}
