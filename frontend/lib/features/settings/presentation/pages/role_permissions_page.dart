import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/role_permissions_matrix.dart';

/// Role permission matrix on `/settings/permissions` (also embedded in the settings hub tab).
class RolePermissionsPage extends ConsumerWidget {
  const RolePermissionsPage({this.embedded = false, super.key});

  /// When true, omits standalone page chrome (for the settings hub tab).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final matrixAsync = ref.watch(rolePermissionsProvider);
    final canAccess = AuthRouteGuard.canAccessPermissionMatrix(auth);

    ref.listen<AsyncValue<RolePermissionsUiState>>(rolePermissionsProvider, (previous, next) {
      final saveMessage = next.value?.saveMessage;
      if (saveMessage != null && saveMessage != previous?.value?.saveMessage) {
        ref.showAppToast(message: saveMessage, variant: AppToastVariant.success);
        ref.read(rolePermissionsProvider.notifier).clearSaveMessage();
      }

      final errorMessage = next.value?.errorMessage;
      if (errorMessage != null && errorMessage != previous?.value?.errorMessage) {
        ref.showAppToast(message: errorMessage, variant: AppToastVariant.danger);
      }
    });

    final body = _RolePermissionsBody(
      canAccess: canAccess,
      matrixAsync: matrixAsync,
      embedded: embedded,
    );

    if (embedded) {
      return body;
    }

    return ColoredBox(color: context.colors.surfaceCanvas, child: body);
  }
}

class _RolePermissionsBody extends ConsumerWidget {
  const _RolePermissionsBody({
    required this.canAccess,
    required this.matrixAsync,
    required this.embedded,
  });

  final bool canAccess;
  final AsyncValue<RolePermissionsUiState> matrixAsync;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canAccess) {
      return const Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.noAccess,
          title: 'Role permissions',
          description: 'Role permissions are available only to clinic administrators.',
        ),
      );
    }

    final content = matrixAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => Center(
        child: AppErrorState(
          message: 'Could not load permission matrix: $error',
          onRetry: () => ref.invalidate(rolePermissionsProvider),
        ),
      ),
      data: (ui) {
        if (ui.permissionDenied) {
          return const Center(
            child: AppEmptyState(
              variant: AppEmptyStateVariant.noAccess,
              title: 'Role permissions',
              description: 'Role permissions are available only to clinic administrators.',
            ),
          );
        }

        if (ui.matrix.permissionKeys.isEmpty) {
          return const Center(
            child: AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: 'No permissions configured',
              description: 'No permission rows are configured for this clinic.',
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(embedded ? AppSpacing.s6 : AppSpacing.s6),
          child: RolePermissionsMatrix(ui: ui),
        );
      },
    );

    if (embedded) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s6,
            AppSpacing.s6,
            AppSpacing.s6,
            AppSpacing.s4,
          ),
          child: AppPageHeader(
            title: 'Role permissions',
            description: 'Configure which actions each staff role can perform.',
            breadcrumb: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
                const AppBreadcrumbItem(label: 'Role permissions'),
              ],
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
