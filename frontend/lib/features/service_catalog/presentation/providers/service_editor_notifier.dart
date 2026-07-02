import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
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
    final auth = ref.watch(authSessionProvider);
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

  Future<String> createService({
    required String name,
    required String defaultPrice,
    required GlobalStatus globalStatus,
    required bool assignAllBranches,
    required Set<String> selectedBranchIds,
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
      final detail = await _repo.getService(serviceId: result.serviceId);
      state = AsyncData(ServiceEditorState(detail: detail));
      return result.serviceId;
    } catch (error) {
      state = AsyncData(current);
      rethrow;
    }
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
      state = AsyncData(ServiceEditorState(detail: detail));
    } catch (error) {
      state = AsyncData(current);
      rethrow;
    }
  }
}
