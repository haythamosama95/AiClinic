import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Builds [FSelect] doctor rows with branch-availability highlighting.
abstract final class AppointmentDoctorSelectItems {
  static const unavailableSubtitle = 'Not available at this branch';

  static List<FSelectItemMixin> build({
    required BuildContext context,
    required String? branchId,
    required List<StaffListItem> doctors,
    required String emptyLabel,
    String emptyValue = '',
  }) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    final available = <StaffListItem>[];
    final unavailable = <StaffListItem>[];
    for (final doctor in doctors) {
      if (_isUnavailableAtBranch(doctor, branchId)) {
        unavailable.add(doctor);
      } else {
        available.add(doctor);
      }
    }
    available.sort(StaffListItem.compareByFullName);
    unavailable.sort(StaffListItem.compareByFullName);

    return [
      FSelectItemMixin.item<String>(
        title: Text(emptyLabel, style: theme.textTheme.bodyMedium),
        value: emptyValue,
      ),
      for (final doctor in available)
        FSelectItemMixin.item<String>(
          title: Text(doctor.fullName, style: theme.textTheme.bodyMedium),
          value: doctor.id,
        ),
      if (unavailable.isNotEmpty)
        FSelectItemMixin.richSection<String>(
          label: Text(
            unavailableSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive, fontWeight: FontWeight.w600),
          ),
          children: [for (final doctor in unavailable) _unavailableDoctorItem(context, theme: theme, doctor: doctor)],
        ),
    ];
  }

  static bool _isUnavailableAtBranch(StaffListItem doctor, String? branchId) {
    return branchId != null && branchId.isNotEmpty && !doctor.isAssignedToBranch(branchId);
  }

  static FSelectItem<String> _unavailableDoctorItem(
    BuildContext context, {
    required ThemeData theme,
    required StaffListItem doctor,
  }) {
    final colors = context.semanticColors;
    final invalidBackground = Color.alphaBlend(colors.destructive.withValues(alpha: 0.22), colors.muted);

    return FSelectItemMixin.raw<String>(
      value: doctor.id,
      child: SizedBox(
        width: double.infinity,
        child: ColoredBox(
          color: invalidBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Text(
              doctor.fullName,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.destructive, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
