import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/data/app_data_table.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_skeleton.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table.dart';

/// Skeleton loader mirroring [PatientsTable] row structure.
class PatientsTableSkeleton extends StatelessWidget {
  const PatientsTableSkeleton({this.rowCount = 12, super.key});

  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      columns: patientTableColumns,
      rowCount: rowCount,
      rowBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: Row(
            children: [
              const AppSkeletonCircle(size: 30),
              const SizedBox(width: SpacingTokens.sm),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(width: 140, height: 12),
                    SizedBox(height: 6),
                    AppSkeletonBox(width: 72, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              const AppSkeletonBox(width: 72, height: 12),
              const SizedBox(width: SpacingTokens.sm),
              const AppSkeletonBox(width: 96, height: 12),
              const SizedBox(width: SpacingTokens.sm),
              const AppSkeletonBox(width: 80, height: 12),
              const SizedBox(width: SpacingTokens.sm),
              const AppSkeletonBox(width: 88, height: 12),
            ],
          ),
        );
      },
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: const Row(
          children: [AppSkeletonBox(width: 160, height: 12), Spacer(), AppSkeletonBox(width: 120, height: 28)],
        ),
      ),
    );
  }
}
