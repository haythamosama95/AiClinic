import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';

const _setupDayToWeekday = <String, BranchWeekday>{
  'mon': BranchWeekday.monday,
  'tue': BranchWeekday.tuesday,
  'wed': BranchWeekday.wednesday,
  'thu': BranchWeekday.thursday,
  'fri': BranchWeekday.friday,
  'sat': BranchWeekday.saturday,
  'sun': BranchWeekday.sunday,
};

BranchWorkingSchedule workingDaysToSchedule(List<WorkingDay> workingDays) {
  final byDayId = {for (final day in workingDays) day.day: day};

  return BranchWorkingSchedule(
    BranchWeekday.values
        .map((weekday) {
          final dayId = _setupDayToWeekday.entries.firstWhere((entry) => entry.value == weekday).key;
          final draftDay = byDayId[dayId];
          if (draftDay == null) {
            return BranchWorkingDayHours(day: weekday, isWorkingDay: false, openTime: null, closeTime: null);
          }
          return BranchWorkingDayHours(
            day: weekday,
            isWorkingDay: draftDay.enabled,
            openTime: draftDay.enabled ? draftDay.openTime : null,
            closeTime: draftDay.enabled ? draftDay.closeTime : null,
          );
        })
        .toList(growable: false),
  );
}

StaffRole? staffRoleFromDraft(String role) {
  final normalized = role.trim().toLowerCase();
  if (normalized == 'owner') {
    return StaffRole.administrator;
  }
  if (normalized == 'nurse') {
    return StaffRole.labStaff;
  }
  return StaffRole.tryParse(role);
}

/// Maps the cached settings setup draft to the atomic bootstrap RPC payload.
///
/// V1 bootstrap creates the first branch atomically with organization and staff.
/// Additional branches and services remain in the local draft until dedicated
/// steady-state APIs are wired for the settings wizard re-run path.
BootstrapFinishSetupInput toBootstrapFinishSetupInput(SetupDraft draft) {
  if (draft.branches.isEmpty) {
    throw StateError('At least one branch is required to finish clinic setup.');
  }
  if (draft.staff.isEmpty) {
    throw StateError('At least one staff member is required to finish clinic setup.');
  }

  final organization = draft.organization;
  final primaryBranch = draft.branches.first;

  final staffAccounts = <CreateStaffAccountInput>[];
  for (final member in draft.staff) {
    final role = staffRoleFromDraft(member.role);
    if (role == null) {
      throw StateError('Staff member "${member.name}" has an unsupported role.');
    }

    staffAccounts.add(
      CreateStaffAccountInput(
        username: normalizeStaffUsername(member.username),
        password: member.password,
        fullName: member.name.trim(),
        role: role,
        branchIds: const [],
        phone: member.mobile.trim().isEmpty ? null : member.mobile.trim(),
      ),
    );
  }

  return BootstrapFinishSetupInput(
    organization: BootstrapOrganizationInput(
      name: organization.name.trim(),
      currencyCode: organization.currency.trim().toUpperCase(),
      timezone: organization.timezone.trim(),
    ),
    branch: BootstrapBranchInput(
      organizationId: '',
      name: primaryBranch.name.trim(),
      code: primaryBranch.code.trim().isEmpty ? null : primaryBranch.code.trim(),
      phone: primaryBranch.mobile.trim().isEmpty ? null : primaryBranch.mobile.trim(),
      mapsUrl: primaryBranch.mapLocation.trim().isEmpty ? null : primaryBranch.mapLocation.trim(),
      workingSchedule: workingDaysToSchedule(primaryBranch.workingDays),
    ),
    staffAccounts: staffAccounts,
  );
}
