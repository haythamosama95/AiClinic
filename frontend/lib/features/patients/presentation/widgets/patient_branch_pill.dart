import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Branch label pill used on patient visit and appointment record cards.
class PatientBranchPill extends StatelessWidget {
  const PatientBranchPill({required this.branchName, super.key});

  final String branchName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1 + AppSpacing.space05,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apartment, size: 14, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space2),
            Flexible(
              child: Text(
                branchName,
                style: AppTypography.bodySm(
                  context,
                ).copyWith(color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
