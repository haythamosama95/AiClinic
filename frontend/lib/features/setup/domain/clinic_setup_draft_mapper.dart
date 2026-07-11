import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
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

const _weekdayToSetupDay = <BranchWeekday, String>{
  BranchWeekday.monday: 'mon',
  BranchWeekday.tuesday: 'tue',
  BranchWeekday.wednesday: 'wed',
  BranchWeekday.thursday: 'thu',
  BranchWeekday.friday: 'fri',
  BranchWeekday.saturday: 'sat',
  BranchWeekday.sunday: 'sun',
};

List<WorkingDay> scheduleToWorkingDays(BranchWorkingSchedule? schedule) {
  final resolved = schedule ?? BranchWorkingSchedule.defaultSchedule();
  return resolved.days
      .map(
        (hours) => WorkingDay(
          day: _weekdayToSetupDay[hours.day] ?? 'mon',
          enabled: hours.isWorkingDay,
          openTime: hours.openTime ?? '09:00',
          closeTime: hours.closeTime ?? '17:00',
        ),
      )
      .toList(growable: false);
}

/// Normalizes backend phone values for display in the setup wizard.
///
/// Egypt national numbers (10 digits, or 12 digits with the `20` country code)
/// are reduced to their 10-digit form. Non-Egypt numbers that are not 10 digits
/// are returned in full rather than silently truncated to the last 10 digits, so
/// admins reviewing international clinics do not see mangled phone values
/// (review §5.4). The 10-digit input is still enforced at entry time.
String normalizeSetupNationalPhone(String? raw) {
  final digits = raw?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.isEmpty) {
    return '';
  }
  if (digits.length == 10) {
    return digits;
  }
  if (digits.length == 12 && digits.startsWith('20')) {
    return digits.substring(2);
  }
  // Any other length: return the full digit string instead of truncating.
  return digits;
}

OrganizationDraft organizationProfileToDraft(OrganizationProfile profile) {
  return OrganizationDraft(
    name: profile.name,
    timezone: profile.timezone ?? 'Africa/Cairo',
    currency: profile.currencyCode ?? 'EGP',
  );
}

BranchDraft branchListItemToDraft(BranchListItem branch) {
  return BranchDraft(
    id: branch.id,
    name: branch.name,
    code: branch.code ?? '',
    mobile: normalizeSetupNationalPhone(branch.phone),
    mapLocation: branch.mapsUrl ?? '',
    workingDays: scheduleToWorkingDays(branch.workingSchedule),
    isDraft: false,
  );
}

String staffRoleToDraftValue(StaffRole role) {
  return switch (role) {
    StaffRole.administrator => 'administrator',
    StaffRole.labStaff => 'lab_staff',
    StaffRole.doctor => 'doctor',
    StaffRole.receptionist => 'receptionist',
  };
}

StaffDraft staffListItemToDraft(StaffListItem staff) {
  return StaffDraft(
    id: staff.id,
    name: staff.fullName,
    mobile: normalizeSetupNationalPhone(staff.phone),
    username: staff.username ?? '',
    password: '',
    role: staffRoleToDraftValue(staff.role),
    branchIds: staff.branches.map((branch) => branch.id).whereType<String>().toList(growable: false),
    isDraft: false,
  );
}

ServiceDraft serviceListItemToDraft(ServiceListItem service) {
  return ServiceDraft(id: service.serviceId, name: service.name, price: service.defaultPrice.asDouble, isDraft: false);
}

/// Builds a setup wizard draft from steady-state backend entities.
SetupDraft setupDraftFromBackend({
  OrganizationProfile? organization,
  List<BranchListItem> branches = const [],
  List<StaffListItem> staff = const [],
  List<ServiceListItem> services = const [],
}) {
  final organizationDraft = organization != null
      ? organizationProfileToDraft(organization)
      : const OrganizationDraft(name: '', timezone: 'Africa/Cairo', currency: 'EGP');

  return SetupDraft(
    organization: organizationDraft,
    branches: branches.isNotEmpty ? branches.map(branchListItemToDraft).toList(growable: false) : [createEmptyBranch()],
    staff: staff.isNotEmpty ? staff.map(staffListItemToDraft).toList(growable: false) : [createEmptyStaff()],
    services: services.isNotEmpty
        ? services.map(serviceListItemToDraft).toList(growable: false)
        : [createEmptyService()],
  );
}

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
  // Backward-compatible aliases for older wizard drafts that used the legacy
  // 'owner'/'nurse' option values before they were aligned with the StaffRole
  // enum (review §5.1). New drafts store 'administrator'/'lab_staff'.
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
