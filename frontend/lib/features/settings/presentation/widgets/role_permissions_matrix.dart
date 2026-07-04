import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';

import 'settings_permission_action.dart';

/// Permission matrix table: roles as columns, permissions grouped by category as rows.
class RolePermissionsMatrix extends ConsumerStatefulWidget {
  const RolePermissionsMatrix({required this.ui, super.key});

  final RolePermissionsUiState ui;

  @override
  ConsumerState<RolePermissionsMatrix> createState() => _RolePermissionsMatrixState();
}

class _RolePermissionsMatrixState extends ConsumerState<RolePermissionsMatrix> {
  late final ScrollController _horizontalHeaderController;
  late final ScrollController _horizontalBodyController;
  var _isSyncingHorizontal = false;

  @override
  void initState() {
    super.initState();
    _horizontalHeaderController = ScrollController();
    _horizontalBodyController = ScrollController();
    _horizontalHeaderController.addListener(_syncBodyToHeaderOffset);
    _horizontalBodyController.addListener(_syncHeaderToBodyOffset);
  }

  @override
  void dispose() {
    _horizontalHeaderController
      ..removeListener(_syncBodyToHeaderOffset)
      ..dispose();
    _horizontalBodyController
      ..removeListener(_syncHeaderToBodyOffset)
      ..dispose();
    super.dispose();
  }

  void _syncBodyToHeaderOffset() {
    if (_isSyncingHorizontal || !_horizontalBodyController.hasClients) {
      return;
    }
    _isSyncingHorizontal = true;
    _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
    _isSyncingHorizontal = false;
  }

  void _syncHeaderToBodyOffset() {
    if (_isSyncingHorizontal || !_horizontalHeaderController.hasClients) {
      return;
    }
    _isSyncingHorizontal = true;
    _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
    _isSyncingHorizontal = false;
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    final roles = PermissionMatrixView.displayRoles;
    final categories = ui.matrix.categoryGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StaffRolesHeader(ui: ui),
        const SizedBox(height: AppSpacing.s3),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _MatrixColumnHeadersDelegate(
                      roles: roles,
                      horizontalController: _horizontalHeaderController,
                      minWidth: constraints.maxWidth,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    sliver: SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _horizontalBodyController,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: IntrinsicWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < categories.length; i++) ...[
                                  if (i > 0) const SizedBox(height: AppSpacing.s4),
                                  _CategoryPermissionCard(ui: ui, group: categories[i], roles: roles),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MatrixColumnHeadersDelegate extends SliverPersistentHeaderDelegate {
  const _MatrixColumnHeadersDelegate({
    required this.roles,
    required this.horizontalController,
    required this.minWidth,
  });

  final List<StaffRole> roles;
  final ScrollController horizontalController;
  final double minWidth;

  static const _headerExtent = 56.0;

  @override
  double get minExtent => _headerExtent;

  @override
  double get maxExtent => _headerExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final colors = context.colors;

    return Material(
      color: colors.surfaceDefault,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: colors.borderSubtle,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: horizontalController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: IntrinsicWidth(
            child: _MatrixColumnHeaders(roles: roles),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MatrixColumnHeadersDelegate oldDelegate) {
    return roles != oldDelegate.roles || minWidth != oldDelegate.minWidth;
  }
}

class _MatrixColumnHeaders extends StatelessWidget {
  const _MatrixColumnHeaders({required this.roles});

  final List<StaffRole> roles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: _MatrixRow(
          showDivider: false,
          children: [
            _PermissionHeaderCell(
              child: Text(
                'Permission',
                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final role in roles)
              _RoleHeaderCell(
                child: Text(
                  PermissionMatrixView.roleLabel(role),
                  textAlign: TextAlign.center,
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPermissionCard extends StatelessWidget {
  const _CategoryPermissionCard({
    required this.ui,
    required this.group,
    required this.roles,
  });

  final RolePermissionsUiState ui;
  final PermissionCategoryGroup group;
  final List<StaffRole> roles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s6,
                AppSpacing.s4,
                AppSpacing.s6,
                AppSpacing.s3,
              ),
              child: Text(
                PermissionMatrixView.categoryLabel(group.category),
                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            for (var i = 0; i < group.permissionKeys.length; i++)
              _MatrixRow(
                showDivider: i < group.permissionKeys.length - 1,
                children: [
                  _PermissionHeaderCell(
                    child: Row(
                      children: [
                        if (roles.any((role) => ui.isCellDirty(role, group.permissionKeys[i])))
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: AppSpacing.s3),
                            child: Icon(Icons.circle, size: 8, color: colors.actionPrimary),
                          ),
                        Expanded(
                          child: Text(
                            PermissionMatrixView.permissionLabel(group.permissionKeys[i]),
                            style: typography.body.copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final role in roles)
                    _RoleHeaderCell(
                      child: _PermissionGrantCheckbox(
                        ui: ui,
                        role: role,
                        permissionKey: group.permissionKeys[i],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StaffRolesHeader extends ConsumerWidget {
  const _StaffRolesHeader({required this.ui});

  final RolePermissionsUiState ui;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Manage access permissions by role',
            style: typography.title.copyWith(color: colors.textPrimary),
          ),
        ),
        if (ui.editable) ...[
          if (ui.hasUnsavedChanges) ...[
            AppButton(
              label: 'Discard',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              disabled: ui.isSaving,
              onPressed: ui.isSaving
                  ? null
                  : () => ref.read(rolePermissionsProvider.notifier).discardChanges(),
            ),
            const SizedBox(width: AppSpacing.s3),
          ],
          AppButton(
            label: 'Save changes',
            size: AppButtonSize.sm,
            loading: ui.isSaving,
            disabled: !ui.hasUnsavedChanges || ui.isSaving,
            onPressed: !ui.hasUnsavedChanges || ui.isSaving
                ? null
                : () => ref.read(rolePermissionsProvider.notifier).saveChanges(),
          ),
        ] else
          SettingsPermissionAction(
            disabledReason: 'Only clinic administrators can edit role permissions.',
            builder: (enabled) => AppButton(
              label: 'Save changes',
              size: AppButtonSize.sm,
              disabled: !enabled,
              onPressed: null,
            ),
          ),
      ],
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.children, required this.showDivider});

  final List<Widget> children;
  final bool showDivider;

  static const _permissionColumnFlex = 25;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                Expanded(
                  flex: i == 0 ? _permissionColumnFlex : 10,
                  child: children[i],
                ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colors.borderSubtle),
      ],
    );
  }
}

class _PermissionHeaderCell extends StatelessWidget {
  const _PermissionHeaderCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s4,
      ),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }
}

class _RoleHeaderCell extends StatelessWidget {
  const _RoleHeaderCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s4,
      ),
      child: Center(child: child),
    );
  }
}

class _PermissionGrantCheckbox extends ConsumerWidget {
  const _PermissionGrantCheckbox({
    required this.ui,
    required this.role,
    required this.permissionKey,
  });

  final RolePermissionsUiState ui;
  final StaffRole role;
  final String permissionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final granted = ui.matrix.isGranted(role, permissionKey);
    final isDirty = ui.isCellDirty(role, permissionKey);
    final canEdit = ui.editable;

    if (!canEdit) {
      return _MatrixCheckboxVisual(value: granted, enabled: false, colors: colors);
    }

    return Material(
      color: isDirty ? colors.surfaceMuted : Colors.transparent,
      child: InkWell(
        onTap: ui.isSaving
            ? null
            : () {
                ref.read(rolePermissionsProvider.notifier).setLocalGrant(
                      role: role,
                      permissionKey: permissionKey,
                      isGranted: !granted,
                    );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
          child: _MatrixCheckboxVisual(value: granted, enabled: !ui.isSaving, colors: colors),
        ),
      ),
    );
  }
}

class _MatrixCheckboxVisual extends StatelessWidget {
  const _MatrixCheckboxVisual({
    required this.value,
    required this.enabled,
    required this.colors,
  });

  final bool value;
  final bool enabled;
  final AppColors colors;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final borderRadius = AppRadii.smAll;

    if (value) {
      return SizedBox(
        width: _size,
        height: _size,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: borderRadius, color: colors.actionPrimary),
          child: Icon(Icons.check, size: 14, color: colors.actionPrimaryFg),
        ),
      );
    }

    final iconColor = enabled ? colors.textSecondary : colors.textDisabled;

    return SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colors.borderSubtle),
          color: enabled ? Colors.transparent : colors.surfaceMuted,
        ),
        child: Icon(Icons.close, size: 14, color: iconColor),
      ),
    );
  }
}
