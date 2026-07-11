import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.start,
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space4,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 672),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Roles & permissions', style: AppTypography.h3(context)),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        'Built-in roles and their access grants. Assign a role when you create or edit a staff account.',
                        style: AppTypography.bodySm(context),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [
                    if (state.hasUnsavedChanges)
                      AppButton(
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.sm,
                        leadingIcon: const Icon(Icons.close, size: 14),
                        disabled: state.isSaving || !state.editable,
                        onPressed: ref.read(rolePermissionsProvider.notifier).discardChanges,
                        child: const Text('Discard'),
                      ),
                    AppButton(
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.save, size: 14),
                      disabled: !state.hasUnsavedChanges || state.isSaving || !state.editable,
                      loading: state.isSaving,
                      onPressed: () => ref.read(rolePermissionsProvider.notifier).saveChanges(),
                      child: const Text('Save changes'),
                    ),
                  ],
                ),
              ],
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
            RolePermissionsMatrix(
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
          ],
        );
      },
      loading: () => const _RolesTabLoadingBody(),
      error: (_, _) =>
          const AppErrorState(title: 'Unable to load permissions', message: 'Check connectivity and try again.'),
    );
  }
}

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
        const AppSkeleton(height: 320),
      ],
    );
  }
}
