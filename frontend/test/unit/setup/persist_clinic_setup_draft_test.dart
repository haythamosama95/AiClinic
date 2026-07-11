import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/persist_clinic_setup_draft.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_organization_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSetupDraftEntityId', () {
    test('returns true for wizard-generated ids', () {
      expect(isSetupDraftEntityId('${DateTime.now().microsecondsSinceEpoch}_1'), isTrue);
    });

    test('returns false for backend UUIDs', () {
      expect(isSetupDraftEntityId('550e8400-e29b-41d4-a716-446655440000'), isFalse);
    });
  });

  group('persistSetupDraftToBackend', () {
    test('updates organization and existing entities while creating new ones', () async {
      final draft = SetupDraft(
        organization: const OrganizationDraft(name: 'Updated Clinic', timezone: 'Africa/Cairo', currency: 'EGP'),
        branches: [
          const BranchDraft(
            id: 'branch-1',
            name: 'Main Updated',
            code: 'MAIN',
            mobile: '1005551234',
            mapLocation: 'https://maps.example/main',
            workingDays: [],
            isDraft: false,
          ),
          BranchDraft(
            id: '1700000000000_1',
            name: 'Second',
            code: 'SEC',
            mobile: '1005559999',
            mapLocation: '',
            workingDays: createDefaultWorkingDays(),
          ),
        ],
        staff: [
          const StaffDraft(
            id: 'staff-1',
            name: 'Dr. Sam Updated',
            mobile: '1005551111',
            username: 'dr.sam',
            password: '',
            role: 'doctor',
            branchIds: ['branch-1', '1700000000000_1'],
            isDraft: false,
          ),
          StaffDraft(
            id: '1700000000000_2',
            name: 'New Receptionist',
            mobile: '1005552222',
            username: 'reception.new',
            password: 'Password1!',
            role: 'receptionist',
            branchIds: ['branch-1'],
          ),
        ],
        services: [
          ServiceDraft(id: 'svc-1', name: 'Consultation Updated', price: 300, isDraft: false),
          ServiceDraft(id: '1700000000000_3', name: 'X-Ray', price: 150),
        ],
      );

      final updatedOrganizations = <UpdateOrganizationInput>[];
      final createdBranches = <CreateBranchInput>[];
      final updatedBranches = <UpdateBranchInput>[];
      final deletedBranchIds = <String>[];
      final createdStaff = <CreateStaffAccountInput>[];
      final updatedStaff = <UpdateStaffMemberInput>[];
      final deletedStaffIds = <String>[];
      final createdServices = <Map<String, String>>[];
      final updatedServices = <Map<String, dynamic>>[];
      final deletedServiceIds = <String>[];

      await persistSetupDraftToBackend(
        draft: draft,
        existingBranches: [
          BranchListItem(
            id: 'branch-1',
            name: 'Main',
            isActive: true,
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
          BranchListItem(
            id: 'branch-old',
            name: 'Old',
            isActive: true,
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        ],
        existingStaff: [
          const StaffListItem(
            id: 'staff-1',
            fullName: 'Dr. Sam',
            role: StaffRole.doctor,
            isActive: true,
            branches: [StaffBranchLabel(id: 'branch-1', name: 'Main', isPrimary: true)],
          ),
          const StaffListItem(
            id: 'staff-old',
            fullName: 'Old Staff',
            role: StaffRole.receptionist,
            isActive: true,
            branches: [],
          ),
        ],
        existingServices: [
          ServiceListItem(
            serviceId: 'svc-1',
            name: 'Consultation',
            defaultPrice: Money.parse('250.00'),
            globalStatus: GlobalStatus.active,
            assignedBranchCount: 1,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          ServiceListItem(
            serviceId: 'svc-old',
            name: 'Old Service',
            defaultPrice: Money.parse('50.00'),
            globalStatus: GlobalStatus.active,
            assignedBranchCount: 1,
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        gateways: PersistSetupDraftGateways(
          updateOrganization: (input) async {
            updatedOrganizations.add(input);
            return 'org-1';
          },
          createBranch: (input) async {
            createdBranches.add(input);
            return 'branch-2';
          },
          updateBranch: (input) async {
            updatedBranches.add(input);
            return input.branchId;
          },
          deleteBranch: ({required String branchId}) async {
            deletedBranchIds.add(branchId);
            return const RpcResult(success: true);
          },
          createStaffAccount: (input) async {
            createdStaff.add(input);
            return null;
          },
          updateStaffMember: (input) async {
            updatedStaff.add(input);
            return input.staffMemberId;
          },
          deleteStaffMember: ({required String staffMemberId}) async {
            deletedStaffIds.add(staffMemberId);
            return const RpcResult(success: true);
          },
          createService: ({required String name, required String defaultPrice}) async {
            createdServices.add({'name': name, 'defaultPrice': defaultPrice});
            return 'svc-2';
          },
          updateService:
              ({
                required String serviceId,
                required DateTime expectedUpdatedAt,
                required String name,
                required String defaultPrice,
              }) async {
                updatedServices.add({
                  'serviceId': serviceId,
                  'name': name,
                  'defaultPrice': defaultPrice,
                  'expectedUpdatedAt': expectedUpdatedAt,
                });
              },
          softDeleteService: ({required String serviceId, required DateTime expectedUpdatedAt}) async {
            deletedServiceIds.add(serviceId);
          },
        ),
      );

      expect(updatedOrganizations, hasLength(1));
      expect(updatedOrganizations.first.name, 'Updated Clinic');

      expect(createdBranches, hasLength(1));
      expect(createdBranches.first.name, 'Second');

      expect(updatedBranches, hasLength(1));
      expect(updatedBranches.first.branchId, 'branch-1');
      expect(updatedBranches.first.name, 'Main Updated');

      expect(deletedBranchIds, ['branch-old']);

      expect(updatedStaff, hasLength(1));
      expect(updatedStaff.first.staffMemberId, 'staff-1');
      expect(updatedStaff.first.branchIds, ['branch-1', 'branch-2']);

      expect(createdStaff, hasLength(1));
      expect(createdStaff.first.username, 'reception.new');
      expect(createdStaff.first.branchIds, ['branch-1']);

      expect(deletedStaffIds, ['staff-old']);

      expect(updatedServices, hasLength(1));
      expect(updatedServices.first['serviceId'], 'svc-1');
      expect(updatedServices.first['defaultPrice'], '300.00');

      expect(createdServices, hasLength(1));
      expect(createdServices.first['name'], 'X-Ray');

      expect(deletedServiceIds, ['svc-old']);
    });

    test('resolves staff branch ids from initialBranchIdMap after bootstrap', () async {
      const primaryBranchBackendId = '550e8400-e29b-41d4-a716-446655440000';
      const primaryBranchDraftId = '1700000000000_1';
      const staffBackendId = '660e8400-e29b-41d4-a716-446655440001';

      final draft = SetupDraft(
        organization: const OrganizationDraft(name: 'Clinic', timezone: 'Africa/Cairo', currency: 'EGP'),
        branches: [
          const BranchDraft(
            id: primaryBranchBackendId,
            name: 'Main',
            code: 'MAIN',
            mobile: '1005551234',
            mapLocation: '',
            workingDays: [],
            isDraft: false,
          ),
        ],
        staff: [
          const StaffDraft(
            id: staffBackendId,
            name: 'Admin',
            mobile: '1005551111',
            username: 'admin',
            password: '',
            role: 'administrator',
            branchIds: [primaryBranchDraftId],
            isDraft: false,
          ),
        ],
        services: const [],
      );

      final updatedStaff = <UpdateStaffMemberInput>[];

      await persistSetupDraftToBackend(
        draft: draft,
        existingBranches: const [],
        existingStaff: const [],
        existingServices: const [],
        initialBranchIdMap: {primaryBranchDraftId: primaryBranchBackendId},
        gateways: PersistSetupDraftGateways(
          updateOrganization: (_) async => 'org-1',
          createBranch: (_) async => 'branch-new',
          updateBranch: (input) async => input.branchId,
          deleteBranch: ({required String branchId}) async => const RpcResult(success: true),
          createStaffAccount: (_) async => null,
          updateStaffMember: (input) async {
            updatedStaff.add(input);
            return input.staffMemberId;
          },
          deleteStaffMember: ({required String staffMemberId}) async => const RpcResult(success: true),
          createService: ({required String name, required String defaultPrice}) async => 'svc-1',
          updateService:
              ({
                required String serviceId,
                required DateTime expectedUpdatedAt,
                required String name,
                required String defaultPrice,
              }) async {},
          softDeleteService: ({required String serviceId, required DateTime expectedUpdatedAt}) async {},
        ),
      );

      expect(updatedStaff, hasLength(1));
      expect(updatedStaff.first.branchIds, [primaryBranchBackendId]);
    });
  });
}
