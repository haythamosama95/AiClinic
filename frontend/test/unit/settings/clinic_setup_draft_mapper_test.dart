import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setupDraftFromBackend', () {
    test('maps organization, branches, staff, and services into a setup draft', () {
      final draft = setupDraftFromBackend(
        organization: const OrganizationProfile(
          id: 'org-1',
          name: 'Nile Dental',
          currencyCode: 'EGP',
          timezone: 'Africa/Cairo',
        ),
        branches: [
          BranchListItem(
            id: 'branch-1',
            name: 'Main',
            isActive: true,
            code: 'MAIN',
            phone: '+201234567890',
            mapsUrl: 'https://maps.example/main',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        ],
        staff: [
          const StaffListItem(
            id: 'staff-1',
            fullName: 'Dr. Sam',
            role: StaffRole.doctor,
            isActive: true,
            phone: '+201111111111',
            username: 'dr.sam',
            branches: [StaffBranchLabel(id: 'branch-1', name: 'Main', isPrimary: true)],
          ),
        ],
        services: [
          ServiceListItem(
            serviceId: 'svc-1',
            name: 'Consultation',
            defaultPrice: Money.parse('250.00'),
            globalStatus: GlobalStatus.active,
            assignedBranchCount: 1,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      expect(draft.organization.name, 'Nile Dental');
      expect(draft.organization.currency, 'EGP');
      expect(draft.branches, hasLength(1));
      expect(draft.branches.first.id, 'branch-1');
      expect(draft.branches.first.code, 'MAIN');
      expect(draft.branches.first.mobile, '1234567890');
      expect(draft.staff, hasLength(1));
      expect(draft.staff.first.username, 'dr.sam');
      expect(draft.staff.first.mobile, '1111111111');
      expect(draft.staff.first.branchIds, ['branch-1']);
      expect(draft.services, hasLength(1));
      expect(draft.services.first.price, 250);
    });

    test('falls back to empty entities when backend lists are empty', () {
      final draft = setupDraftFromBackend();

      expect(draft.organization.name, isEmpty);
      expect(draft.branches, hasLength(1));
      expect(draft.staff, hasLength(1));
      expect(draft.services, hasLength(1));
    });
  });

  group('normalizeSetupNationalPhone', () {
    test('strips Egypt country code from 12-digit values', () {
      expect(normalizeSetupNationalPhone('+20 100 555 1234'), '1005551234');
      expect(normalizeSetupNationalPhone('201005551234'), '1005551234');
    });

    test('keeps 10-digit national numbers', () {
      expect(normalizeSetupNationalPhone('1005551234'), '1005551234');
    });
  });
}
