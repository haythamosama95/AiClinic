import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/setup/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';

typedef UpdateOrganizationFn = Future<String> Function(UpdateOrganizationInput input);
typedef CreateBranchFn = Future<String> Function(CreateBranchInput input);
typedef UpdateBranchFn = Future<String> Function(UpdateBranchInput input);
typedef DeleteBranchFn = Future<RpcResult> Function({required String branchId});
typedef CreateStaffAccountFn = Future<dynamic> Function(CreateStaffAccountInput input);
typedef UpdateStaffMemberFn = Future<String> Function(UpdateStaffMemberInput input);
typedef DeleteStaffMemberFn = Future<RpcResult> Function({required String staffMemberId});
typedef CreateServiceFn = Future<String> Function({required String name, required String defaultPrice});
typedef UpdateServiceFn =
    Future<void> Function({
      required String serviceId,
      required DateTime expectedUpdatedAt,
      required String name,
      required String defaultPrice,
    });
typedef SoftDeleteServiceFn = Future<void> Function({required String serviceId, required DateTime expectedUpdatedAt});

/// RPC gateways used to persist a settings setup draft for a configured clinic.
class PersistSetupDraftGateways {
  const PersistSetupDraftGateways({
    required this.updateOrganization,
    required this.createBranch,
    required this.updateBranch,
    required this.deleteBranch,
    required this.createStaffAccount,
    required this.updateStaffMember,
    required this.deleteStaffMember,
    required this.createService,
    required this.updateService,
    required this.softDeleteService,
  });

  final UpdateOrganizationFn updateOrganization;
  final CreateBranchFn createBranch;
  final UpdateBranchFn updateBranch;
  final DeleteBranchFn deleteBranch;
  final CreateStaffAccountFn createStaffAccount;
  final UpdateStaffMemberFn updateStaffMember;
  final DeleteStaffMemberFn deleteStaffMember;
  final CreateServiceFn createService;
  final UpdateServiceFn updateService;
  final SoftDeleteServiceFn softDeleteService;
}

/// Persists a validated setup draft to steady-state backend APIs.
Future<void> persistSetupDraftToBackend({
  required SetupDraft draft,
  required PersistSetupDraftGateways gateways,
  required List<BranchListItem> existingBranches,
  required List<StaffListItem> existingStaff,
  required List<ServiceListItem> existingServices,
  Map<String, String> initialBranchIdMap = const {},
}) async {
  await gateways.updateOrganization(
    UpdateOrganizationInput(
      name: draft.organization.name.trim(),
      currencyCode: draft.organization.currency.trim().toUpperCase(),
      timezone: draft.organization.timezone.trim(),
    ),
  );

  final branchIdMap = Map<String, String>.from(initialBranchIdMap);
  for (final branch in draft.branches) {
    final schedule = workingDaysToSchedule(branch.workingDays);
    final phone = branch.mobile.trim().isEmpty ? null : branch.mobile.trim();
    final code = branch.code.trim().isEmpty ? null : branch.code.trim();
    final mapsUrl = branch.mapLocation.trim().isEmpty ? null : branch.mapLocation.trim();

    if (branch.isDraft) {
      final backendId = await gateways.createBranch(
        CreateBranchInput(
          name: branch.name.trim(),
          workingSchedule: schedule,
          code: code,
          phone: phone,
          mapsUrl: mapsUrl,
        ),
      );
      branchIdMap[branch.id] = backendId;
    } else {
      await gateways.updateBranch(
        UpdateBranchInput(
          branchId: branch.id,
          name: branch.name.trim(),
          workingSchedule: schedule,
          code: code,
          phone: phone,
          mapsUrl: mapsUrl,
        ),
      );
    }
  }

  final draftBackendBranchIds = draft.branches
      .map((branch) => branchIdMap[branch.id] ?? branch.id)
      .where((id) => !isSetupDraftEntityId(id))
      .toSet();
  for (final branch in existingBranches) {
    if (!draftBackendBranchIds.contains(branch.id)) {
      await gateways.deleteBranch(branchId: branch.id);
    }
  }

  final draftBackendStaffIds = <String>{};
  for (final member in draft.staff) {
    final role = staffRoleFromDraft(member.role);
    if (role == null) {
      throw StateError('Staff member "${member.name}" has an unsupported role.');
    }

    final branchIds = _resolveBranchIds(member.branchIds, branchIdMap);
    final phone = member.mobile.trim().isEmpty ? null : member.mobile.trim();

    if (member.isDraft) {
      await gateways.createStaffAccount(
        CreateStaffAccountInput(
          username: normalizeStaffUsername(member.username),
          password: member.password,
          fullName: member.name.trim(),
          role: role,
          branchIds: branchIds,
          primaryBranchId: branchIds.isEmpty ? null : branchIds.first,
          phone: phone,
        ),
      );
    } else {
      draftBackendStaffIds.add(member.id);
      await gateways.updateStaffMember(
        UpdateStaffMemberInput(
          staffMemberId: member.id,
          fullName: member.name.trim(),
          role: role,
          branchIds: branchIds,
          primaryBranchId: branchIds.isEmpty ? null : branchIds.first,
          phone: phone,
        ),
      );
    }
  }

  for (final member in existingStaff) {
    if (!draftBackendStaffIds.contains(member.id)) {
      await gateways.deleteStaffMember(staffMemberId: member.id);
    }
  }

  final existingServicesById = {for (final service in existingServices) service.serviceId: service};
  final draftBackendServiceIds = <String>{};
  for (final service in draft.services) {
    final defaultPrice = _serviceDefaultPriceWire(service.price);

    if (service.isDraft) {
      await gateways.createService(name: service.name.trim(), defaultPrice: defaultPrice);
    } else {
      draftBackendServiceIds.add(service.id);
      final existing = existingServicesById[service.id];
      if (existing == null) {
        throw StateError('Service "${service.name}" is missing from the backend catalog.');
      }

      await gateways.updateService(
        serviceId: service.id,
        expectedUpdatedAt: existing.updatedAt,
        name: service.name.trim(),
        defaultPrice: defaultPrice,
      );
    }
  }

  for (final service in existingServices) {
    if (!draftBackendServiceIds.contains(service.serviceId) && !isSetupDraftEntityId(service.serviceId)) {
      await gateways.softDeleteService(serviceId: service.serviceId, expectedUpdatedAt: service.updatedAt);
    }
  }
}

List<String> _resolveBranchIds(List<String> branchIds, Map<String, String> branchIdMap) {
  return branchIds.map((id) => branchIdMap[id] ?? id).toList(growable: false);
}

String _serviceDefaultPriceWire(double? price) {
  if (price == null) {
    throw StateError('Each service must have a default price before finishing setup.');
  }
  return Money.parse(price.toStringAsFixed(2)).wireValue;
}
