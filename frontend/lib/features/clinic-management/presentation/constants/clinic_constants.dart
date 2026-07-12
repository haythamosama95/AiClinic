import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:flutter/foundation.dart';

/// ISO 4217 currency codes for organization settings combobox.
const kCurrencyCodes = <String>[
  'AED',
  'AUD',
  'BHD',
  'CAD',
  'CHF',
  'CNY',
  'EGP',
  'EUR',
  'GBP',
  'INR',
  'JOD',
  'JPY',
  'KWD',
  'OMR',
  'QAR',
  'SAR',
  'TRY',
  'USD',
  'ZAR',
];

/// IANA timezone ids for organization settings combobox.
const kTimezones = <String>[
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Lagos',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/New_York',
  'America/Toronto',
  'Asia/Baghdad',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Kuwait',
  'Asia/Qatar',
  'Asia/Riyadh',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Europe/Berlin',
  'Europe/London',
  'Europe/Paris',
  'UTC',
];

@immutable
class ClinicWeekdayEntry {
  const ClinicWeekdayEntry({required this.id, required this.label});

  final String id;
  final String label;
}

/// Weekday catalog for working-hours editors and summaries.
final kWeekdays = <ClinicWeekdayEntry>[
  for (final day in BranchWeekday.values) ClinicWeekdayEntry(id: day.wireValue, label: day.label),
];

@immutable
class StaffRoleOption {
  const StaffRoleOption({required this.value, required this.label});

  final StaffRole value;
  final String label;
}

/// Staff role select options (order matches web `STAFF_ROLES`).
const kStaffRoles = <StaffRoleOption>[
  StaffRoleOption(value: StaffRole.administrator, label: 'Administrator'),
  StaffRoleOption(value: StaffRole.doctor, label: 'Doctor'),
  StaffRoleOption(value: StaffRole.receptionist, label: 'Receptionist'),
  StaffRoleOption(value: StaffRole.labStaff, label: 'Lab staff'),
];

/// Display labels keyed by staff role.
const kRoleLabels = <StaffRole, String>{
  StaffRole.administrator: 'Administrator',
  StaffRole.doctor: 'Doctor',
  StaffRole.receptionist: 'Receptionist',
  StaffRole.labStaff: 'Lab staff',
};

const kUsernameHint =
    '3–32 characters. Letters, numbers, dots, underscores, and hyphens. Must start with a letter.';

const kPasswordHint = 'At least 8 characters with uppercase, lowercase, and a number.';
