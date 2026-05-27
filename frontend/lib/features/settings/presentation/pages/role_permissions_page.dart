import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Role permission matrix: owners and administrators edit toggles (US5).
class RolePermissionsPage extends ConsumerWidget {
  const RolePermissionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final matrixAsync = ref.watch(rolePermissionsProvider);

    ref.listen<AsyncValue<RolePermissionsUiState>>(rolePermissionsProvider, (previous, next) {
      final saveMessage = next.value?.saveMessage;
      if (saveMessage != null && saveMessage != previous?.value?.saveMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saveMessage)));
        ref.read(rolePermissionsProvider.notifier).clearSaveMessage();
      }

      final errorMessage = next.value?.errorMessage;
      if (errorMessage != null && errorMessage != previous?.value?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    });

    if (!AuthRouteGuard.canAccessPermissionMatrix(auth)) {
      return _scaffold(
        context,
        ref: ref,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Role permissions are available only to clinic owners and administrators.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return matrixAsync.when(
      loading: () => _scaffold(
        context,
        ref: ref,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _scaffold(
        context,
        ref: ref,
        body: Center(child: Text('Could not load permission matrix: $error')),
      ),
      data: (ui) {
        if (ui.permissionDenied) {
          return _scaffold(
            context,
            ref: ref,
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Role permissions are available only to clinic owners and administrators.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (ui.matrix.permissionKeys.isEmpty) {
          return _scaffold(
            context,
            ref: ref,
            body: const Center(child: Text('No permission rows are configured for this clinic.')),
          );
        }

        return _scaffold(context, ref: ref, ui: ui);
      },
    );
  }

  Widget _scaffold(BuildContext context, {required WidgetRef ref, RolePermissionsUiState? ui, Widget? body}) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: ui == null || !ui.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && ui != null && ui.hasUnsavedChanges) {
          _confirmLeave(context, ref, ui);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Role permissions'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => _leavePage(context, ref, ui)),
          actions: [
            if (ui != null && ui.editable)
              TextButton(
                onPressed: !ui.hasUnsavedChanges || ui.isSaving
                    ? null
                    : () => ref.read(rolePermissionsProvider.notifier).saveChanges(),
                child: ui.isSaving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                      )
                    : const Text('Save changes'),
              ),
          ],
        ),
        body: body ?? _MatrixBody(ui: ui!),
      ),
    );
  }

  Future<void> _leavePage(BuildContext context, WidgetRef ref, RolePermissionsUiState? ui) async {
    if (ui == null || !ui.hasUnsavedChanges) {
      if (context.mounted) {
        context.go(AppRoutes.settings);
      }
      return;
    }
    await _confirmLeave(context, ref, ui);
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref, RolePermissionsUiState ui) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have unsaved permission changes. Save them before leaving, or discard your edits.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop('discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop('save'), child: const Text('Save')),
        ],
      ),
    );

    if (!context.mounted) {
      return;
    }

    switch (choice) {
      case 'discard':
        ref.read(rolePermissionsProvider.notifier).discardChanges();
        context.go(AppRoutes.settings);
      case 'save':
        final saved = await ref.read(rolePermissionsProvider.notifier).saveChanges();
        if (saved && context.mounted) {
          context.go(AppRoutes.settings);
        }
      default:
        break;
    }
  }
}

class _MatrixBody extends ConsumerWidget {
  const _MatrixBody({required this.ui});

  final RolePermissionsUiState ui;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roles = PermissionMatrixView.displayRoles;
    final categories = ui.matrix.categoryGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth - 32),
                  child: Table(
                    columnWidths: {
                      0: const FlexColumnWidth(2.5),
                      for (var i = 0; i < roles.length; i++) i + 1: const FlexColumnWidth(1),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: theme.dividerColor),
                      verticalInside: BorderSide(color: theme.dividerColor),
                      top: BorderSide(color: theme.dividerColor),
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Text('Permission', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          for (final role in roles)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              child: Text(
                                PermissionMatrixView.roleLabel(role),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                      for (final group in categories) ...[
                        TableRow(
                          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Text(
                                PermissionMatrixView.categoryLabel(group.category),
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            for (final _ in roles) const SizedBox.shrink(),
                          ],
                        ),
                        for (final permissionKey in group.permissionKeys)
                          _permissionRow(context, ref, permissionKey: permissionKey, roles: roles),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  TableRow _permissionRow(
    BuildContext context,
    WidgetRef ref, {
    required String permissionKey,
    required List<StaffRole> roles,
  }) {
    final theme = Theme.of(context);
    final categoryDirty = roles.any((role) => ui.isCellDirty(role, permissionKey));

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (categoryDirty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.circle, size: 8, color: theme.colorScheme.tertiary),
                ),
              Expanded(
                child: Text(
                  PermissionMatrixView.permissionLabel(permissionKey),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        for (final role in roles)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: _GrantCell(ui: ui, role: role, permissionKey: permissionKey),
          ),
      ],
    );
  }
}

class _GrantCell extends ConsumerWidget {
  const _GrantCell({required this.ui, required this.role, required this.permissionKey});

  final RolePermissionsUiState ui;
  final StaffRole role;
  final String permissionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final granted = ui.matrix.isGranted(role, permissionKey);
    final isDirty = ui.isCellDirty(role, permissionKey);
    final highlightColor = theme.colorScheme.tertiaryContainer.withValues(alpha: isDirty ? 0.85 : 0);
    final canEdit = ui.editable && ui.matrix.hasDefinedCell(role, permissionKey);

    if (!canEdit) {
      return ColoredBox(
        color: highlightColor,
        child: Center(child: Icon(granted ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 20)),
      );
    }

    return ColoredBox(
      color: highlightColor,
      child: Center(
        child: Switch(
          value: granted,
          onChanged: ui.isSaving
              ? null
              : (value) {
                  ref
                      .read(rolePermissionsProvider.notifier)
                      .setLocalGrant(role: role, permissionKey: permissionKey, isGranted: value);
                },
        ),
      ),
    );
  }
}
