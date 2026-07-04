import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';

/// Inline banner for shift overlap conflicts (V1-7 US1).
class ShiftConflictBanner extends StatelessWidget {
  const ShiftConflictBanner({required this.conflicts, super.key});

  final List<ShiftOverlapConflict> conflicts;

  static String formatMessage(List<ShiftOverlapConflict> conflicts) {
    if (conflicts.isEmpty) {
      return 'One or more staff members already have an overlapping shift at this branch.';
    }

    return conflicts.map((c) => '${c.displayName} is already scheduled ${c.startTime}–${c.endTime}.').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return AppAlert(
      key: const Key('shift_conflict_banner'),
      variant: AppAlertVariant.danger,
      title: 'Scheduling conflict',
      body: formatMessage(conflicts),
    );
  }
}
