import 'package:flutter/material.dart';

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
    final colors = Theme.of(context).colorScheme;
    final message = formatMessage(conflicts);

    return Material(
      key: const Key('shift_conflict_banner'),
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_busy, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
