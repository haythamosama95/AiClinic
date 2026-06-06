import 'package:flutter/material.dart';

import 'package:ai_clinic/features/shifts/domain/shift_status.dart';

/// Compact status chip for shift calendar and detail views (V1-7 US2).
class ShiftStatusBadge extends StatelessWidget {
  const ShiftStatusBadge({required this.status, this.isUnassigned = false, super.key});

  final ShiftStatus status;
  final bool isUnassigned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (status) {
      ShiftStatus.incomplete => (
        isUnassigned ? 'Unassigned' : 'Incomplete',
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ShiftStatus.active => ('Active', scheme.primaryContainer, scheme.onPrimaryContainer),
      ShiftStatus.cancelled => ('Cancelled', scheme.errorContainer, scheme.onErrorContainer),
      ShiftStatus.unknown => ('Unknown', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      key: Key('shift_status_badge_${status.wireValue}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
