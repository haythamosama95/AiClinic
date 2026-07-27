import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/application/clinic_data_changed_provider.dart';
import 'package:ai_clinic/features/appointments/application/appointment_surface_invalidation.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/setup/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/setup/domain/persist_clinic_setup_draft.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Encapsulates cross-feature clinic-data persistence and hydration so the
/// setup notifier does not import settings/service_catalog/appointments
/// directly (review §6.2).
///
/// Owns:
/// - steady-state CRUD persistence (`persistSetupDraftToBackend`)
/// - backend hydration (org/branches/staff/services fetch → draft)
/// - clinic-data-changed signal bump (replaces direct appointment invalidation)
class ClinicSetupOrchestrator {
  ClinicSetupOrchestrator(this._ref);

  final Ref _ref;

  /// Persists a validated draft via steady-state CRUD APIs.
  ///
  /// Fetches the current backend state (branches/staff/services) then delegates
  /// to [persistSetupDraftToBackend]. Throws on RPC failure so the caller can
  /// surface the error.
  Future<void> persistSteadyState(SetupDraft draft) async {
    final organizationId = _currentOrganizationId();
    if (organizationId == null) {
      throw StateError('Sign in again to save clinic setup.');
    }

    final existingBranches = await _ref
        .read(listBranchesUseCaseProvider)(organizationId: organizationId)
        .catchError((_) => const <BranchListItem>[]);
    final existingStaff = await _loadStaffForSetup();
    final existingServices = await _loadServicesForSetup();

    await persistSetupDraftToBackend(
      draft: draft,
      existingBranches: existingBranches,
      existingStaff: existingStaff,
      existingServices: existingServices,
      gateways: _buildPersistGateways(),
    );
  }

  /// Persists extra branches/staff-assignments/services after the atomic
  /// bootstrap RPC committed. [primaryBranchId] and [staffMemberIds] remap the
  /// draft's primary branch + staff to their backend ids.
  Future<void> persistRemainingBootstrapEntities({
    required String primaryBranchId,
    required List<String> staffMemberIds,
    required SetupDraft draft,
  }) async {
    final initialBranchIdMap = <String, String>{};
    final remappedBranches = List<BranchDraft>.of(draft.branches);
    if (remappedBranches.isNotEmpty) {
      final primaryBranchDraftId = remappedBranches[0].id;
      initialBranchIdMap[primaryBranchDraftId] = primaryBranchId;
      remappedBranches[0] = remappedBranches[0].copyWith(id: primaryBranchId, isDraft: false);
    }
    final remappedStaff = <StaffDraft>[];
    for (var i = 0; i < draft.staff.length; i++) {
      final backendId = i < staffMemberIds.length ? staffMemberIds[i] : draft.staff[i].id;
      remappedStaff.add(draft.staff[i].copyWith(id: backendId, isDraft: false));
    }
    final remappedDraft = draft.copyWith(branches: remappedBranches, staff: remappedStaff);

    await persistSetupDraftToBackend(
      draft: remappedDraft,
      existingBranches: const <BranchListItem>[],
      existingStaff: const <StaffListItem>[],
      existingServices: const <ServiceListItem>[],
      initialBranchIdMap: initialBranchIdMap,
      gateways: _buildPersistGateways(),
    );
  }

  /// Fetches organization, branches, staff, and services from the backend and
  /// builds a hydrated [SetupDraft]. Returns `null` when no organization exists
  /// yet (first-run bootstrap).
  Future<SetupDraft?> hydrateDraftFromBackend() async {
    final organizationId = _currentOrganizationId();
    if (organizationId == null || organizationId.isEmpty) {
      return null;
    }
    final session = _ref.read(authSessionProvider).context;
    if (session == null || session.needsClinicSetup) {
      return null;
    }

    final organization = await _ref
        .read(fetchOrganizationProfileUseCaseProvider)(organizationId: organizationId)
        .catchError((_) => null);
    final branches = await _ref
        .read(listBranchesUseCaseProvider)(organizationId: organizationId)
        .catchError((_) => const <BranchListItem>[]);
    final staff = await _loadStaffForSetup();
    final services = await _loadServicesForSetup();

    return setupDraftFromBackend(organization: organization, branches: branches, staff: staff, services: services);
  }

  /// Signals that clinic-wide data changed so downstream features (appointments,
  /// etc.) refresh their cached state. Replaces direct
  /// `invalidateAllAppointmentSurfaces` calls from the notifier (review §6.2).
  void notifyClinicDataChanged() {
    // Bump the decoupled signal so listening features invalidate themselves.
    _ref.read(clinicDataChangedProvider.notifier).bump();
    // Also invalidate the appointment surface providers directly during the
    // transition period so existing listeners that haven't migrated yet still
    // refresh. This is safe to remove once appointments listens to the signal.
    invalidateAllAppointmentSurfaces(_ref);
  }

  String? _currentOrganizationId() {
    final session = _ref.read(authSessionProvider).context;
    return session?.organizationId?.trim();
  }

  PersistSetupDraftGateways _buildPersistGateways() {
    final serviceRepo = _ref.read(serviceCatalogRepositoryProvider);
    return PersistSetupDraftGateways(
      updateOrganization: (input) => _ref.read(updateOrganizationUseCaseProvider)(input),
      createBranch: (input) => _ref.read(createBranchUseCaseProvider)(input),
      updateBranch: (input) => _ref.read(updateBranchUseCaseProvider)(input),
      deleteBranch: ({required String branchId}) => _ref.read(deleteBranchUseCaseProvider)(branchId: branchId),
      createStaffAccount: (input) => _ref.read(createStaffAccountUseCaseProvider)(input),
      updateStaffMember: (input) => _ref.read(updateStaffMemberUseCaseProvider)(input),
      deleteStaffMember: ({required String staffMemberId}) =>
          _ref.read(deleteStaffMemberUseCaseProvider)(staffMemberId: staffMemberId),
      createService: ({required String name, required String defaultPrice}) async {
        final result = await serviceRepo.createService(
          name: name,
          defaultPrice: defaultPrice,
          globalStatus: GlobalStatus.active,
          assignAllBranches: true,
        );
        return result.serviceId;
      },
      updateService:
          ({
            required String serviceId,
            required DateTime expectedUpdatedAt,
            required String name,
            required String defaultPrice,
          }) async {
            await serviceRepo.updateService(
              serviceId: serviceId,
              expectedUpdatedAt: expectedUpdatedAt,
              name: name,
              defaultPrice: defaultPrice,
              globalStatus: GlobalStatus.active,
            );
          },
      softDeleteService: ({required String serviceId, required DateTime expectedUpdatedAt}) async {
        await serviceRepo.softDeleteService(serviceId: serviceId, expectedUpdatedAt: expectedUpdatedAt);
      },
    );
  }

  Future<List<StaffListItem>> _loadStaffForSetup() async {
    final auth = _ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return const [];
    }
    return _ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.all).catchError((_) => const <StaffListItem>[]);
  }

  Future<List<ServiceListItem>> _loadServicesForSetup() async {
    final auth = _ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessServiceCatalogList(auth)) {
      return const [];
    }

    const pageSize = 100;
    var offset = 0;
    final all = <ServiceListItem>[];
    while (true) {
      final page = await _ref
          .read(serviceCatalogRepositoryProvider)
          .listServices(limit: pageSize, offset: offset)
          .catchError((_) => const ServiceListPageResult(items: [], total: 0));
      all.addAll(page.items);
      if (page.items.isEmpty || all.length >= page.total) {
        break;
      }
      offset += pageSize;
    }
    return all;
  }
}

final clinicSetupOrchestratorProvider = Provider<ClinicSetupOrchestrator>((ref) {
  return ClinicSetupOrchestrator(ref);
});
