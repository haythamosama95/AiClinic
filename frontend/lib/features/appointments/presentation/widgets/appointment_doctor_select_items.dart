import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

/// Builds [AppSelectOption] rows with branch-availability highlighting.
abstract final class AppointmentDoctorSelectItems {
  static const unavailableReason = 'Not available at this branch';

  static List<AppSelectOption> buildOptions({
    required String? branchId,
    required List<StaffListItem> doctors,
    required String emptyLabel,
    String emptyValue = '',
  }) {
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
      AppSelectOption(value: emptyValue, label: emptyLabel),
      for (final doctor in available) AppSelectOption(value: doctor.id, label: doctor.fullName),
      for (final doctor in unavailable)
        AppSelectOption(
          value: doctor.id,
          label: doctor.fullName,
          disabled: true,
          disabledReason: unavailableReason,
        ),
    ];
  }

  static bool _isUnavailableAtBranch(StaffListItem doctor, String? branchId) {
    return branchId != null && branchId.isNotEmpty && !doctor.isAssignedToBranch(branchId);
  }
}
