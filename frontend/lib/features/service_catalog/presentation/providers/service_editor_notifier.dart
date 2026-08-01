import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';

@immutable
class ServiceEditorState {
  const ServiceEditorState({this.detail, this.isSaving = false});

  final ServiceDetail? detail;
  final bool isSaving;

  bool get isCreateMode => detail == null;

  ServiceEditorState copyWith({ServiceDetail? detail, bool? isSaving}) {
    return ServiceEditorState(detail: detail ?? this.detail, isSaving: isSaving ?? this.isSaving);
  }
}

/// Create/load service editor state (Service Catalog 015 US1).
final serviceEditorProvider = AsyncNotifierProvider.autoDispose
    .family<ServiceEditorNotifier, ServiceEditorState, String?>(ServiceEditorNotifier.new);

class ServiceEditorNotifier extends AsyncNotifier<ServiceEditorState> {
  ServiceEditorNotifier(this._serviceId);

  /// `null` means create mode.
  final String? _serviceId;

  @override
  Future<ServiceEditorState> build() async {
<<<<<<< HEAD
    final auth = ref.watch(authSessionProvider);
=======
    final auth = ref.read(authSessionProvider);
>>>>>>> master
    if (!AuthRouteGuard.canAccessServiceEditor(auth)) {
      return const ServiceEditorState();
    }

    final serviceId = _serviceId;
    if (serviceId == null || serviceId.isEmpty) {
      return const ServiceEditorState();
    }

    final detail = await ref.read(serviceCatalogRepositoryProvider).getService(serviceId: serviceId);
    return ServiceEditorState(detail: detail);
  }

  ServiceCatalogRepository get _repo => ref.read(serviceCatalogRepositoryProvider);

<<<<<<< HEAD
=======
  void _setStateIfMounted(ServiceEditorState next) {
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(next);
  }

>>>>>>> master
  Future<String> createService({
    required String name,
    required String defaultPrice,
    required GlobalStatus globalStatus,
    required bool assignAllBranches,
    required Set<String> selectedBranchIds,
    List<PendingBranchConfiguration> pendingBranchConfigs = const [],
  }) async {
    final current = state.value ?? const ServiceEditorState();
    state = AsyncData(current.copyWith(isSaving: true));
    try {
      final result = await _repo.createService(
        name: name,
        defaultPrice: defaultPrice,
        globalStatus: globalStatus,
        assignAllBranches: assignAllBranches,
        branchIds: selectedBranchIds.toList(growable: false),
      );
      var detail = await _repo.getService(serviceId: result.serviceId);
      if (pendingBranchConfigs.isNotEmpty) {
        detail = await _applyPendingBranchConfigurations(
          serviceId: result.serviceId,
          detail: detail,
          pendingBranchConfigs: pendingBranchConfigs,
        );
      }
<<<<<<< HEAD
      state = AsyncData(ServiceEditorState(detail: detail));
      return result.serviceId;
    } catch (error) {
      state = AsyncData(current);
=======
      if (!ref.mounted) {
        return result.serviceId;
      }
      _setStateIfMounted(ServiceEditorState(detail: detail));
      return result.serviceId;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<ServiceDetail> _applyPendingBranchConfigurations({
    required String serviceId,
    required ServiceDetail detail,
    required List<PendingBranchConfiguration> pendingBranchConfigs,
  }) async {
    var currentDetail = detail;

    for (final pending in pendingBranchConfigs) {
      final row = currentDetail.branches.where((branch) => branch.branchId == pending.branchId).firstOrNull;
      if (row == null) {
        continue;
      }

      if (pending.hasBranchSettingsChange) {
        final updatedAt = row.updatedAt;
        if (updatedAt == null) {
          throw StateError('Branch configuration timestamp is missing.');
        }
        await _repo.configureServiceBranch(
          serviceId: serviceId,
          branchId: pending.branchId,
          expectedUpdatedAt: updatedAt,
          status: pending.active ? 'active' : 'inactive',
          priceOverride: pending.priceOverride,
        );
        currentDetail = await _repo.getService(serviceId: serviceId);
      }

      if (pending.hasPromotion) {
        final refreshedRow = currentDetail.branches.where((branch) => branch.branchId == pending.branchId).firstOrNull;
        final updatedAt = refreshedRow?.updatedAt;
        if (updatedAt == null) {
          throw StateError('Branch configuration timestamp is missing.');
        }
        final promotion = pending.promotion!;
        await _repo.setServicePromotion(
          serviceId: serviceId,
          branchId: pending.branchId,
          expectedUpdatedAt: updatedAt,
          promotionPrice: promotion.wirePrice,
          startDate: promotion.startDate,
          endDate: promotion.endDate,
        );
        currentDetail = await _repo.getService(serviceId: serviceId);
      }
    }

    return currentDetail;
  }

  Future<void> setBranchAssignment({required List<String> branchIds, required bool assign}) async {
    final current = state.value;
    final serviceId = current?.detail?.service.id ?? _serviceId;
    if (current == null || serviceId == null || serviceId.isEmpty) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
    try {
      await _repo.setBranchAssignment(serviceId: serviceId, branchIds: branchIds, assign: assign);
      final detail = await _repo.getService(serviceId: serviceId);
<<<<<<< HEAD
      state = AsyncData(ServiceEditorState(detail: detail));
    } catch (error) {
      state = AsyncData(current);
=======
      _setStateIfMounted(ServiceEditorState(detail: detail));
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<void> reloadDetail() async {
    final serviceId = state.value?.detail?.service.id ?? _serviceId;
    if (serviceId == null || serviceId.isEmpty) {
      return;
    }
    final detail = await _repo.getService(serviceId: serviceId);
<<<<<<< HEAD
    state = AsyncData(ServiceEditorState(detail: detail));
=======
    _setStateIfMounted(ServiceEditorState(detail: detail));
  }

  /// Loads [ServiceDetail] when edit-mode state was lost (e.g. autoDispose recreation).
  Future<ServiceDetail> _ensureDetailLoaded() async {
    final existing = state.value?.detail;
    if (existing != null) {
      return existing;
    }

    final serviceId = _serviceId;
    if (serviceId == null || serviceId.isEmpty) {
      throw StateError('Service not loaded.');
    }

    final detail = await _repo.getService(serviceId: serviceId);
    _setStateIfMounted(ServiceEditorState(detail: detail));
    return detail;
>>>>>>> master
  }

  Future<void> configureServiceBranch({
    required String branchId,
    required DateTime expectedUpdatedAt,
    required bool active,
    String? priceOverride,
  }) async {
    final current = state.value;
    final serviceId = current?.detail?.service.id ?? _serviceId;
    if (current == null || serviceId == null || serviceId.isEmpty) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
    try {
      await _repo.configureServiceBranch(
        serviceId: serviceId,
        branchId: branchId,
        expectedUpdatedAt: expectedUpdatedAt,
        status: active ? 'active' : 'inactive',
        priceOverride: priceOverride,
      );
      final detail = await _repo.getService(serviceId: serviceId);
<<<<<<< HEAD
      state = AsyncData(ServiceEditorState(detail: detail));
=======
      _setStateIfMounted(ServiceEditorState(detail: detail));
>>>>>>> master
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE_BRANCH') {
        await reloadDetail();
      }
<<<<<<< HEAD
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
    } catch (error) {
      state = AsyncData(current);
=======
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false));
      }
      rethrow;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<void> setServicePromotion({
    required String branchId,
    required DateTime expectedUpdatedAt,
    String? promotionPrice,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final current = state.value;
    final serviceId = current?.detail?.service.id ?? _serviceId;
    if (current == null || serviceId == null || serviceId.isEmpty) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
    try {
      await _repo.setServicePromotion(
        serviceId: serviceId,
        branchId: branchId,
        expectedUpdatedAt: expectedUpdatedAt,
        promotionPrice: promotionPrice,
        startDate: startDate,
        endDate: endDate,
      );
      final detail = await _repo.getService(serviceId: serviceId);
<<<<<<< HEAD
      state = AsyncData(ServiceEditorState(detail: detail));
=======
      _setStateIfMounted(ServiceEditorState(detail: detail));
>>>>>>> master
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE_BRANCH') {
        await reloadDetail();
      }
<<<<<<< HEAD
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
    } catch (error) {
      state = AsyncData(current);
=======
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false));
      }
      rethrow;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<void> clearServicePromotion({required String branchId, required DateTime expectedUpdatedAt}) {
    return setServicePromotion(
      branchId: branchId,
      expectedUpdatedAt: expectedUpdatedAt,
      promotionPrice: null,
      startDate: null,
      endDate: null,
    );
  }

  Future<void> updateService({
    required String name,
    required String defaultPrice,
    required GlobalStatus globalStatus,
    required bool assignAllBranches,
    required Set<String> selectedBranchIds,
    required List<String> allBranchIds,
  }) async {
<<<<<<< HEAD
    final current = state.value;
    final detail = current?.detail;
    final serviceId = detail?.service.id ?? _serviceId;
    final updatedAt = detail?.service.updatedAt;
    if (current == null || serviceId == null || serviceId.isEmpty || updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
=======
    final current = state.value ?? const ServiceEditorState();
    final detail = await _ensureDetailLoaded();
    if (!ref.mounted) {
      return;
    }
    final serviceId = detail.service.id;
    final updatedAt = detail.service.updatedAt;
    if (updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true, detail: detail));
>>>>>>> master
    try {
      await _repo.updateService(
        serviceId: serviceId,
        expectedUpdatedAt: updatedAt,
        name: name,
        defaultPrice: defaultPrice,
        globalStatus: globalStatus,
      );

<<<<<<< HEAD
      final currentAssigned = {for (final row in detail!.branches) row.branchId};
=======
      final currentAssigned = {for (final row in detail.branches) row.branchId};
>>>>>>> master
      final targetAssigned = assignAllBranches ? allBranchIds.toSet() : selectedBranchIds;
      final toAssign = targetAssigned.difference(currentAssigned).toList(growable: false);
      final toUnassign = currentAssigned.difference(targetAssigned).toList(growable: false);

      if (toAssign.isNotEmpty) {
        await _repo.setBranchAssignment(serviceId: serviceId, branchIds: toAssign, assign: true);
      }
      if (toUnassign.isNotEmpty) {
        await _repo.setBranchAssignment(serviceId: serviceId, branchIds: toUnassign, assign: false);
      }

      final refreshed = await _repo.getService(serviceId: serviceId);
<<<<<<< HEAD
      state = AsyncData(ServiceEditorState(detail: refreshed));
=======
      _setStateIfMounted(ServiceEditorState(detail: refreshed));
>>>>>>> master
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE') {
        await reloadDetail();
      }
<<<<<<< HEAD
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
    } catch (error) {
      state = AsyncData(current);
=======
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false));
      }
      rethrow;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<void> setGlobalStatus(GlobalStatus globalStatus) async {
<<<<<<< HEAD
    final current = state.value;
    final detail = current?.detail;
    final serviceId = detail?.service.id ?? _serviceId;
    final updatedAt = detail?.service.updatedAt;
    if (current == null || serviceId == null || serviceId.isEmpty || updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
    try {
      await _repo.setGlobalStatus(serviceId: serviceId, expectedUpdatedAt: updatedAt, globalStatus: globalStatus);
      final refreshed = await _repo.getService(serviceId: serviceId);
      state = AsyncData(ServiceEditorState(detail: refreshed));
=======
    final current = state.value ?? const ServiceEditorState();
    final detail = await _ensureDetailLoaded();
    if (!ref.mounted) {
      return;
    }
    final serviceId = detail.service.id;
    final updatedAt = detail.service.updatedAt;
    if (updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true, detail: detail));
    try {
      await _repo.setGlobalStatus(serviceId: serviceId, expectedUpdatedAt: updatedAt, globalStatus: globalStatus);
      final refreshed = await _repo.getService(serviceId: serviceId);
      _setStateIfMounted(ServiceEditorState(detail: refreshed));
>>>>>>> master
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE') {
        await reloadDetail();
      }
<<<<<<< HEAD
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
    } catch (error) {
      state = AsyncData(current);
=======
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false));
      }
      rethrow;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }

  Future<void> softDeleteService() async {
<<<<<<< HEAD
    final current = state.value;
    final detail = current?.detail;
    final serviceId = detail?.service.id ?? _serviceId;
    final updatedAt = detail?.service.updatedAt;
    if (current == null || serviceId == null || serviceId.isEmpty || updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true));
    try {
      await _repo.softDeleteService(serviceId: serviceId, expectedUpdatedAt: updatedAt);
      state = AsyncData(const ServiceEditorState());
=======
    final current = state.value ?? const ServiceEditorState();
    final detail = await _ensureDetailLoaded();
    if (!ref.mounted) {
      return;
    }
    final serviceId = detail.service.id;
    final updatedAt = detail.service.updatedAt;
    if (updatedAt == null) {
      throw StateError('Service not loaded.');
    }

    state = AsyncData(current.copyWith(isSaving: true, detail: detail));
    try {
      await _repo.softDeleteService(serviceId: serviceId, expectedUpdatedAt: updatedAt);
      _setStateIfMounted(const ServiceEditorState());
>>>>>>> master
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_SERVICE') {
        await reloadDetail();
      }
<<<<<<< HEAD
      state = AsyncData(current.copyWith(isSaving: false));
      rethrow;
    } catch (error) {
      state = AsyncData(current);
=======
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false));
      }
      rethrow;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current);
      }
>>>>>>> master
      rethrow;
    }
  }
}
