import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
<<<<<<< HEAD
=======
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/permission_matrix_view.dart';
>>>>>>> master
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_tab_header.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/role_permissions_matrix.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/role_permissions_notifier.dart';

/// Roles & permissions tab with draft grant matrix (web `RolesTab`).
class RolesTab extends ConsumerWidget {
  const RolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionsState = ref.watch(rolePermissionsProvider);

    return permissionsState.when(
      data: (state) {
        if (state.permissionDenied) {
          return const AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Permission denied',
            description: 'You do not have access to view or edit role permissions.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClinicTabHeader(
              title: 'Roles & permissions',
              description:
                  'Built-in roles and their access grants. Assign a role when you create or edit a staff account.',
              actions: Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  if (state.hasUnsavedChanges)
                    AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.lg,
                      leadingIcon: const Icon(Icons.close, size: 16),
                      disabled: state.isSaving || !state.editable,
                      onPressed: ref.read(rolePermissionsProvider.notifier).discardChanges,
                      child: const Text('Discard'),
                    ),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.lg,
                    leadingIcon: const Icon(Icons.save, size: 16),
                    disabled: !state.hasUnsavedChanges || state.isSaving || !state.editable,
                    loading: state.isSaving,
                    onPressed: () => ref.read(rolePermissionsProvider.notifier).saveChanges(),
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.space4),
              AppErrorState(title: 'Unable to save permissions', message: state.errorMessage!),
            ],
            if (state.saveMessage != null) ...[
              const SizedBox(height: AppSpacing.space4),
              AppAlert(variant: AppAlertVariant.success, title: state.saveMessage!),
            ],
            const SizedBox(height: AppSpacing.space6),
            SizedBox(
              width: double.infinity,
<<<<<<< HEAD
              child: RolePermissionsMatrix(
=======
              child: _DeferredRolePermissionsMatrix(
>>>>>>> master
                matrix: state.workingMatrix,
                savedMatrix: state.savedMatrix,
                editable: state.editable,
                isCellDirty: state.isCellDirty,
                onToggle: ({required role, required permissionKey}) {
                  final granted = state.workingMatrix.isGranted(role, permissionKey);
                  ref
                      .read(rolePermissionsProvider.notifier)
                      .setLocalGrant(role: role, permissionKey: permissionKey, isGranted: !granted);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const _RolesTabLoadingBody(),
      error: (_, _) =>
          const AppErrorState(title: 'Unable to load permissions', message: 'Check connectivity and try again.'),
    );
  }
}

<<<<<<< HEAD
=======
/// Defers mounting the heavy grant matrix until after the tab transition frame.
class _DeferredRolePermissionsMatrix extends StatefulWidget {
  const _DeferredRolePermissionsMatrix({
    required this.matrix,
    required this.savedMatrix,
    required this.editable,
    required this.onToggle,
    required this.isCellDirty,
  });

  final PermissionMatrixView matrix;
  final PermissionMatrixView savedMatrix;
  final bool editable;
  final RoleGrantToggleCallback onToggle;
  final bool Function(StaffRole role, String permissionKey) isCellDirty;

  @override
  State<_DeferredRolePermissionsMatrix> createState() => _DeferredRolePermissionsMatrixState();
}

class _DeferredRolePermissionsMatrixState extends State<_DeferredRolePermissionsMatrix> {
  var _matrixReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _matrixReady = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_matrixReady) {
      return const _RolePermissionsMatrixSkeleton();
    }

    return RolePermissionsMatrix(
      matrix: widget.matrix,
      savedMatrix: widget.savedMatrix,
      editable: widget.editable,
      isCellDirty: widget.isCellDirty,
      onToggle: widget.onToggle,
    );
  }
}

class _RolePermissionsMatrixSkeleton extends StatelessWidget {
  const _RolePermissionsMatrixSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSkeleton(height: 56),
        const SizedBox(height: AppSpacing.space4),
        for (var index = 0; index < 3; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space4),
          const AppSkeleton(height: 160),
        ],
      ],
    );
  }
}

>>>>>>> master
class _RolesTabLoadingBody extends StatelessWidget {
  const _RolesTabLoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppSkeleton(height: 24, width: 220),
        const SizedBox(height: AppSpacing.space2),
        const AppSkeleton(height: 16, width: 480),
        const SizedBox(height: AppSpacing.space6),
<<<<<<< HEAD
        const AppSkeleton(height: 320),
=======
        const _RolePermissionsMatrixSkeleton(),
>>>>>>> master
      ],
    );
  }
}
