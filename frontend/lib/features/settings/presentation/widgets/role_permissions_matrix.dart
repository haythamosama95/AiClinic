import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';

/// Permission matrix table: roles as columns, permissions grouped by category as rows.
class RolePermissionsMatrix extends ConsumerStatefulWidget {
  const RolePermissionsMatrix({required this.ui, super.key});

  final RolePermissionsUiState ui;

  static const _permissionColumnFlex = 2.5;
  static const _checkboxSize = 20.0;

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
    if (_isSyncingHorizontal) {
      return;
    }
    if (!_horizontalBodyController.hasClients) {
      return;
    }
    _isSyncingHorizontal = true;
    _horizontalBodyController.jumpTo(_horizontalHeaderController.offset);
    _isSyncingHorizontal = false;
  }

  void _syncHeaderToBodyOffset() {
    if (_isSyncingHorizontal) {
      return;
    }
    if (!_horizontalHeaderController.hasClients) {
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
        const SizedBox(height: SpacingTokens.sm),
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
                    padding: const EdgeInsets.only(top: SpacingTokens.md),
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
                                  if (i > 0) const SizedBox(height: SpacingTokens.md),
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
  const _MatrixColumnHeadersDelegate({required this.roles, required this.horizontalController, required this.minWidth});

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
    final colors = context.semanticColors;

    return Material(
      color: colors.card,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: colors.border,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: horizontalController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: IntrinsicWidth(
            child: _MatrixColumnHeaders(roles: roles, pinned: overlapsContent),
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
  const _MatrixColumnHeaders({required this.roles, this.pinned = false});

  final List<StaffRole> roles;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: pinned ? null : BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: pinned ? BorderRadius.zero : BorderRadius.circular(context.shapeTokens.lg),
        child: _MatrixRow(
          showDivider: false,
          children: [
            _PermissionHeaderCell(
              child: Text(
                'Permission',
                style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
              ),
            ),
            for (final role in roles)
              _RoleHeaderCell(
                child: Text(
                  PermissionMatrixView.roleLabel(role),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPermissionCard extends StatelessWidget {
  const _CategoryPermissionCard({required this.ui, required this.group, required this.roles});

  final RolePermissionsUiState ui;
  final PermissionCategoryGroup group;
  final List<StaffRole> roles;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.lg,
                SpacingTokens.md,
                SpacingTokens.lg,
                SpacingTokens.sm,
              ),
              child: Text(
                PermissionMatrixView.categoryLabel(group.category),
                style: theme.textTheme.titleSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700),
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.border),
            for (var i = 0; i < group.permissionKeys.length; i++)
              _MatrixRow(
                showDivider: i < group.permissionKeys.length - 1,
                children: [
                  _PermissionHeaderCell(
                    child: Row(
                      children: [
                        if (roles.any((role) => ui.isCellDirty(role, group.permissionKeys[i])))
                          Padding(
                            padding: const EdgeInsets.only(right: SpacingTokens.sm),
                            child: Icon(Icons.circle, size: 8, color: colors.primary),
                          ),
                        Expanded(
                          child: Text(
                            PermissionMatrixView.permissionLabel(group.permissionKeys[i]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final role in roles)
                    _RoleHeaderCell(
                      child: _PermissionGrantCheckbox(ui: ui, role: role, permissionKey: group.permissionKeys[i]),
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
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Manage access permissions by role',
              style: theme.textTheme.titleMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
            ),
          ),
          if (ui.editable) ...[
            if (ui.hasUnsavedChanges) ...[
              AppButton(
                label: 'Discard',
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: ui.isSaving ? null : () => ref.read(rolePermissionsProvider.notifier).discardChanges(),
              ),
              const SizedBox(width: SpacingTokens.sm),
            ],
            AppButton(
              label: 'Save changes',
              expand: false,
              isLoading: ui.isSaving,
              onPressed: !ui.hasUnsavedChanges || ui.isSaving
                  ? null
                  : () => ref.read(rolePermissionsProvider.notifier).saveChanges(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.children, required this.showDivider});

  final List<Widget> children;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                Expanded(
                  flex: i == 0 ? (RolePermissionsMatrix._permissionColumnFlex * 10).round() : 10,
                  child: children[i],
                ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: colors.border),
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
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}

class _RoleHeaderCell extends StatelessWidget {
  const _RoleHeaderCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.md),
      child: Center(child: child),
    );
  }
}

class _PermissionGrantCheckbox extends ConsumerWidget {
  const _PermissionGrantCheckbox({required this.ui, required this.role, required this.permissionKey});

  final RolePermissionsUiState ui;
  final StaffRole role;
  final String permissionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.semanticColors;
    final granted = ui.matrix.isGranted(role, permissionKey);
    final isDirty = ui.isCellDirty(role, permissionKey);
    final canEdit = ui.editable;

    if (!canEdit) {
      return _MatrixCheckboxVisual(value: granted, enabled: false, colors: colors);
    }

    return Material(
      color: isDirty ? colors.accent.withValues(alpha: 0.35) : Colors.transparent,
      child: InkWell(
        onTap: ui.isSaving
            ? null
            : () {
                ref
                    .read(rolePermissionsProvider.notifier)
                    .setLocalGrant(role: role, permissionKey: permissionKey, isGranted: !granted);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
          child: _MatrixCheckboxVisual(value: granted, enabled: !ui.isSaving, colors: colors),
        ),
      ),
    );
  }
}

class _MatrixCheckboxVisual extends StatelessWidget {
  const _MatrixCheckboxVisual({required this.value, required this.enabled, required this.colors});

  final bool value;
  final bool enabled;
  final SemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(context.shapeTokens.sm);
    final size = RolePermissionsMatrix._checkboxSize;

    if (value) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: borderRadius, color: colors.primary),
          child: Icon(Icons.check, size: 14, color: colors.primaryForeground),
        ),
      );
    }

    final iconColor = enabled ? colors.mutedForeground : colors.mutedForeground.withValues(alpha: 0.65);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colors.border),
          color: enabled ? Colors.transparent : colors.muted.withValues(alpha: 0.35),
        ),
        child: Icon(Icons.close, size: 14, color: iconColor),
      ),
    );
  }
}
