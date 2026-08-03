import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Badge color per staff role (web `ROLE_BADGE_COLORS`).
const kRoleBadgeColors = <StaffRole, BadgeColor>{
  StaffRole.administrator: BadgeColor.ai,
  StaffRole.doctor: BadgeColor.teal,
  StaffRole.receptionist: BadgeColor.info,
  StaffRole.labStaff: BadgeColor.neutral,
};

@immutable
class RoleAccentGradient {
  const RoleAccentGradient({required this.start, required this.end});

  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(colors: [start, end]);
}

/// Column header accent gradient per role (web `ROLE_ACCENTS`).
const kRoleAccents = <StaffRole, RoleAccentGradient>{
  StaffRole.administrator: RoleAccentGradient(start: AppColorPrimitives.violet500, end: AppColorPrimitives.violet700),
  StaffRole.doctor: RoleAccentGradient(start: AppColorPrimitives.teal500, end: AppColorPrimitives.teal700),
  StaffRole.receptionist: RoleAccentGradient(start: AppColorPrimitives.neutral500, end: AppColorPrimitives.neutral600),
  StaffRole.labStaff: RoleAccentGradient(start: AppColorPrimitives.neutral400, end: AppColorPrimitives.neutral600),
};

/// One-line role scope summary for matrix header tooltips (web `ROLE_SUMMARIES`).
const kRoleSummaries = <StaffRole, String>{
  StaffRole.administrator: 'Organization admin — staff, branches, billing, and the permission matrix.',
  StaffRole.doctor: 'Clinical staff — patients, appointments, visits, attachments, and AI.',
  StaffRole.receptionist: 'Front desk — patients, appointments, invoices, and payments.',
  StaffRole.labStaff: 'Laboratory — view patients and upload visit attachments.',
};
