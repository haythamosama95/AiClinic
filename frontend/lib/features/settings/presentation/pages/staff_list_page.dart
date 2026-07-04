import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_permission_action.dart';

/// Staff administration list on `/settings/staff` (also embedded in the settings hub tab).
class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({this.embedded = false, super.key});

  /// When true, omits standalone page chrome (for the settings hub tab).
  final bool embedded;

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  final _searchController = TextEditingController();
  var _query = const StaffListQuery();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = _query.copyWith(searchText: value));
  }

  List<StaffListItem> _filtered(List<StaffListItem> staff) {
    final filtered = staff.where(_query.matches).toList()..sort(StaffListItem.compareByFullName);
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canAccess = AuthRouteGuard.canAccessStaffManagement(auth);
    final permissions = ref.watch(permissionServiceProvider);
    final listAsync = ref.watch(staffListProvider);

    if (!canAccess) {
      final body = const Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.noAccess,
          title: 'Staff management',
          description: 'You do not have permission to manage staff.',
        ),
      );
      return widget.embedded ? body : ColoredBox(color: context.colors.surfaceCanvas, child: body);
    }

    final content = listAsync.when(
      loading: () => _buildShell(
        context,
        permissions: permissions,
        body: AppTable<StaffListItem>(
          columns: _columns(context),
          rowId: (row) => row.id,
          stickyFirstColumn: true,
          loading: true,
        ),
      ),
      error: (error, _) => _buildShell(
        context,
        permissions: permissions,
        body: AppTable<StaffListItem>(
          columns: _columns(context),
          rowId: (row) => row.id,
          stickyFirstColumn: true,
          error: error,
          onRetry: () => ref.read(staffListProvider.notifier).reload(),
        ),
      ),
      data: (state) {
        final filtered = _filtered(state.staff);

        return _buildShell(
          context,
          permissions: permissions,
          body: AppTable<StaffListItem>(
            columns: _columns(context),
            rowId: (row) => row.id,
            stickyFirstColumn: true,
            data: filtered,
            filteredEmpty: filtered.isEmpty && state.staff.isNotEmpty,
            onRowTap: widget.embedded
                ? (member) => context.nav.goSettingsStaffDetail(member.id)
                : (member) => context.nav.goSettingsStaffDetail(member.id),
            emptyState: const AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: 'No staff yet',
              description: 'Create an account to get started.',
            ),
            filteredEmptyState: const AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: 'No staff match your search',
              description: 'Try a different name, username, or phone number.',
            ),
          ),
        );
      },
    );

    return widget.embedded ? content : ColoredBox(color: context.colors.surfaceCanvas, child: content);
  }

  Widget _buildShell(
    BuildContext context, {
    required PermissionService permissions,
    required Widget body,
  }) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s6,
              AppSpacing.s4,
              AppSpacing.s6,
              AppSpacing.s4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    hintText: 'Search staff…',
                    onValueChange: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                SettingsPermissionAction(
                  disabledReason: permissions.canManageStaff()
                      ? null
                      : 'You do not have permission to manage staff.',
                  builder: (enabled) => AppButton(
                    label: 'New staff',
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.userPlus,
                    disabled: !enabled,
                    onPressed: enabled ? () => context.nav.goSettingsStaffNew() : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return ListIndexPattern(
      title: 'Staff',
      description: 'Search and manage staff accounts at your clinic.',
      breadcrumb: AppBreadcrumb(
        items: [
          AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
          const AppBreadcrumbItem(label: 'Staff'),
        ],
      ),
      headerActions: SettingsPermissionAction(
        disabledReason: permissions.canManageStaff()
            ? null
            : 'You do not have permission to manage staff.',
        builder: (enabled) => AppButton(
          label: 'New staff',
          size: AppButtonSize.sm,
          leadingIcon: LucideIcons.userPlus,
          disabled: !enabled,
          onPressed: enabled ? () => context.nav.goSettingsStaffNew() : null,
        ),
      ),
      toolbarStart: SizedBox(
        width: 280,
        child: AppSearchField(
          controller: _searchController,
          hintText: 'Search by name, username, or phone…',
          onValueChange: _onSearchChanged,
        ),
      ),
      table: body,
      page: 1,
      pageCount: 1,
      onPageChanged: (_) {},
    );
  }

  static List<AppTableColumn<StaffListItem>> _columns(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return [
      AppTableColumn(
        id: 'name',
        header: 'Staff member',
        flex: 3,
        sticky: true,
        cellBuilder: (context, member) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              member.fullName,
              style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (member.username != null)
              Text(
                member.username!,
                style: typography.caption.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
      AppTableColumn(
        id: 'role',
        header: 'Role',
        width: 128,
        cellBuilder: (context, member) => Text(member.role.displayLabel),
      ),
      AppTableColumn(
        id: 'status',
        header: 'Status',
        width: 108,
        cellBuilder: (context, member) => AppBadge(
          color: member.isActive ? AppBadgeColor.success : AppBadgeColor.neutral,
          child: Text(member.isActive ? 'Active' : 'Inactive'),
        ),
      ),
      AppTableColumn(
        id: 'branches',
        header: 'Branches',
        flex: 2,
        cellBuilder: (context, member) {
          final labels = member.branches;
          if (labels.isEmpty) {
            return const Text('—');
          }
          final text = labels
              .map((branch) => branch.isPrimary ? '${branch.name} (primary)' : branch.name)
              .join(', ');
          return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
        },
      ),
      AppTableColumn(
        id: 'phone',
        header: 'Phone',
        width: 128,
        cellBuilder: (context, member) => Text(
          member.phone ?? '—',
          style: typography.tabular(typography.bodySm),
        ),
      ),
    ];
  }
}
