import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

@immutable
class RolePermissionsUiState {
  const RolePermissionsUiState({
    required this.savedMatrix,
    required this.workingMatrix,
    this.editable = false,
    this.permissionDenied = false,
    this.isSaving = false,
    this.errorMessage,
    this.saveMessage,
  });

  final PermissionMatrixView savedMatrix;
  final PermissionMatrixView workingMatrix;
  final bool editable;
  final bool permissionDenied;
  final bool isSaving;
  final String? errorMessage;
  final String? saveMessage;

  PermissionMatrixView get matrix => workingMatrix;

  bool get hasUnsavedChanges => savedMatrix != workingMatrix;

  bool isCellDirty(StaffRole role, String permissionKey) {
    return savedMatrix.isGranted(role, permissionKey) != workingMatrix.isGranted(role, permissionKey);
  }

  RolePermissionsUiState copyWith({
    PermissionMatrixView? savedMatrix,
    PermissionMatrixView? workingMatrix,
    bool? editable,
    bool? permissionDenied,
    bool? isSaving,
    String? errorMessage,
    String? saveMessage,
    bool clearError = false,
    bool clearSaveMessage = false,
  }) {
    return RolePermissionsUiState(
      savedMatrix: savedMatrix ?? this.savedMatrix,
      workingMatrix: workingMatrix ?? this.workingMatrix,
      editable: editable ?? this.editable,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      saveMessage: clearSaveMessage ? null : (saveMessage ?? this.saveMessage),
    );
  }
}

final rolePermissionsProvider = AsyncNotifierProvider<RolePermissionsNotifier, RolePermissionsUiState>(
  RolePermissionsNotifier.new,
);

class RolePermissionsNotifier extends AsyncNotifier<RolePermissionsUiState> {
  @override
  Future<RolePermissionsUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessPermissionMatrix(auth)) {
      final empty = PermissionMatrixView.fromRows(const []);
      return RolePermissionsUiState(savedMatrix: empty, workingMatrix: empty, permissionDenied: true);
    }

    final rows = await ref.read(fetchPermissionMatrixUseCaseProvider)();
    final matrix = PermissionMatrixView.fromRows(rows);
    final role = auth.context!.staffProfile.role;
    final editable = role == StaffRole.owner || role == StaffRole.administrator;
    return RolePermissionsUiState(savedMatrix: matrix, workingMatrix: matrix, editable: editable);
  }

  void clearSaveMessage() {
    final current = state.value;
    if (current == null || current.saveMessage == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearSaveMessage: true));
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  void discardChanges() {
    final current = state.value;
    if (current == null || current.permissionDenied || !current.hasUnsavedChanges) {
      return;
    }

    state = AsyncData(current.copyWith(workingMatrix: current.savedMatrix, clearError: true, clearSaveMessage: true));
  }

  void setLocalGrant({required StaffRole role, required String permissionKey, required bool isGranted}) {
    final current = state.value;
    if (current == null ||
        current.permissionDenied ||
        !current.editable ||
        current.isSaving ||
        !current.workingMatrix.hasDefinedCell(role, permissionKey)) {
      return;
    }

    state = AsyncData(
      current.copyWith(
        workingMatrix: current.workingMatrix.withGrant(role: role, permissionKey: permissionKey, isGranted: isGranted),
        clearError: true,
        clearSaveMessage: true,
      ),
    );
  }

  Future<bool> saveChanges() async {
    final current = state.value;
    if (current == null || current.permissionDenied || !current.editable || current.isSaving) {
      return false;
    }

    final changes = current.workingMatrix.changesFrom(current.savedMatrix).toList();
    if (changes.isEmpty) {
      return true;
    }

    state = AsyncData(current.copyWith(isSaving: true, clearError: true, clearSaveMessage: true));
    AppLog.info('settings.permissions.save.start count=${changes.length}');

    try {
      for (final change in changes) {
        await ref.read(updateRolePermissionUseCaseProvider)(
          role: change.role,
          permissionKey: change.permissionKey,
          isGranted: change.isGranted,
        );
      }

      final rows = await ref.read(fetchPermissionMatrixUseCaseProvider)();
      final matrix = PermissionMatrixView.fromRows(rows);
      state = AsyncData(
        RolePermissionsUiState(
          savedMatrix: matrix,
          workingMatrix: matrix,
          editable: true,
          saveMessage: 'Role permissions saved. Your session permissions were refreshed.',
        ),
      );

      await ref.read(authNotifierProvider.notifier).reloadContext();
      AppLog.info('settings.permissions.save.ok');
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('settings.permissions.save.rpc_failed code=${error.code}');
      state = AsyncData(current.copyWith(isSaving: false, errorMessage: permissionMessageForRpc(error)));
      return false;
    } catch (error) {
      AppLog.warning('settings.permissions.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Unable to save role permissions. Check connectivity and try again.',
        ),
      );
      return false;
    }
  }
}
