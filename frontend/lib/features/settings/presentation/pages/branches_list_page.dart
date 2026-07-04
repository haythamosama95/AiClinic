import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_permission_action.dart';

/// Branch administration list on `/settings/branches`.
class BranchesListPage extends ConsumerWidget {
  const BranchesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final canManage = AuthRouteGuard.canAccessBranchManagement(auth);
    final permissions = ref.watch(permissionServiceProvider);
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    if (!canManage) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Branches',
            description: 'You do not have permission to manage branches.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: branchesAsync.when(
        loading: () => ColoredBox(
          color: context.colors.surfaceCanvas,
          child: ListIndexPattern(
            title: 'Branches',
            description: 'Manage clinic locations and working hours.',
            breadcrumb: _breadcrumb(context),
            table: const Center(child: AppSpinner()),
            page: 1,
            pageCount: 1,
            onPageChanged: (_) {},
          ),
        ),
        error: (error, _) => ListIndexPattern(
          title: 'Branches',
          description: 'Manage clinic locations and working hours.',
          breadcrumb: _breadcrumb(context),
          headerActions: _newBranchButton(context, permissions),
          table: AppTable<BranchListItem>(
            columns: _columns(context, ref),
            rowId: _rowId,
            stickyFirstColumn: true,
            error: error,
            onRetry: () => ref.invalidate(clinicSetupBranchesProvider),
          ),
          page: 1,
          pageCount: 1,
          onPageChanged: (_) {},
        ),
        data: (branches) => ListIndexPattern(
          title: 'Branches',
          description: 'Manage clinic locations and working hours.',
          breadcrumb: _breadcrumb(context),
          headerActions: _newBranchButton(context, permissions),
          table: AppTable<BranchListItem>(
            columns: _columns(context, ref),
            rowId: _rowId,
            stickyFirstColumn: true,
            data: branches,
            onRowTap: (branch) => context.nav.goSettingsBranchEdit(branch.id),
            emptyState: AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: 'No branches yet',
              description: 'Create a branch to start assigning staff and scheduling.',
            ),
          ),
          page: 1,
          pageCount: 1,
          onPageChanged: (_) {},
        ),
      ),
    );
  }

  static String _rowId(BranchListItem row) => row.id;

  static Widget _breadcrumb(BuildContext context) {
    return AppBreadcrumb(
      items: [
        AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
        const AppBreadcrumbItem(label: 'Branches'),
      ],
    );
  }

  static Widget _newBranchButton(BuildContext context, PermissionService permissions) {
    final disabledReason = permissions.canManageBranches()
        ? null
        : 'You do not have permission to manage branches.';
    return SettingsPermissionAction(
      disabledReason: disabledReason,
      builder: (enabled) => AppButton(
        label: 'New branch',
        size: AppButtonSize.sm,
        leadingIcon: LucideIcons.plus,
        disabled: !enabled,
        onPressed: enabled ? () => context.nav.goSettingsBranchesNew() : null,
      ),
    );
  }

  static List<AppTableColumn<BranchListItem>> _columns(BuildContext context, WidgetRef ref) {
    final typography = context.typography;
    final colors = context.colors;

    return [
      AppTableColumn(
        id: 'name',
        header: 'Branch',
        flex: 3,
        sticky: true,
        cellBuilder: (context, branch) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              branch.name,
              style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (branch.code != null)
              Text(
                branch.code!,
                style: typography.caption.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
      AppTableColumn(
        id: 'status',
        header: 'Status',
        width: 108,
        cellBuilder: (context, branch) => AppBadge(
          color: branch.isActive ? AppBadgeColor.success : AppBadgeColor.neutral,
          child: Text(branch.isActive ? 'Active' : 'Inactive'),
        ),
      ),
      AppTableColumn(
        id: 'phone',
        header: 'Phone',
        width: 128,
        cellBuilder: (context, branch) => Text(
          branch.phone ?? '—',
          style: typography.tabular(typography.bodySm),
        ),
      ),
      AppTableColumn(
        id: 'address',
        header: 'Address',
        flex: 2,
        cellBuilder: (context, branch) => Text(
          branch.address ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
  }
}
