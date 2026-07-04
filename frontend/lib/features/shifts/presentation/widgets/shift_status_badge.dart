import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';

/// Compact status chip for shift calendar and detail views (V1-7 US2).
class ShiftStatusBadge extends StatelessWidget {
  const ShiftStatusBadge({required this.status, this.isUnassigned = false, super.key});

  final ShiftStatus status;
  final bool isUnassigned;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      key: Key('shift_status_badge_${status.wireValue}'),
      color: switch (status) {
        ShiftStatus.incomplete => AppBadgeColor.warning,
        ShiftStatus.active => AppBadgeColor.success,
        ShiftStatus.cancelled => AppBadgeColor.danger,
        ShiftStatus.unknown => AppBadgeColor.neutral,
      },
      child: Text(
        switch (status) {
          ShiftStatus.incomplete => isUnassigned ? 'Unassigned' : 'Incomplete',
          ShiftStatus.active => 'Active',
          ShiftStatus.cancelled => 'Cancelled',
          ShiftStatus.unknown => 'Unknown',
        },
      ),
    );
  }
}
