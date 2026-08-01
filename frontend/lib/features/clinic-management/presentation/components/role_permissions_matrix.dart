import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/permission_matrix.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/role_theme.dart';

typedef RoleGrantToggleCallback = void Function({required StaffRole role, required String permissionKey});

const double _kMinMatrixTableWidth = 704;

/// Permission grant matrix grid (web `RolePermissionsMatrix`).
class RolePermissionsMatrix extends StatelessWidget {
  const RolePermissionsMatrix({
    required this.matrix,
    required this.savedMatrix,
    required this.editable,
    required this.onToggle,
    this.isCellDirty,
    super.key,
  });

  final PermissionMatrixView matrix;
  final PermissionMatrixView savedMatrix;
  final bool editable;
  final RoleGrantToggleCallback onToggle;
  final bool Function(StaffRole role, String permissionKey)? isCellDirty;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final groups = matrix.categoryGroups;

<<<<<<< HEAD
=======
    if (groups.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.space6),
          child: AppEmptyState(
            title: 'No permissions configured',
            description: 'Permission keys are not available for this organization.',
          ),
        ),
      );
    }

>>>>>>> master
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = _matrixTableWidth(constraints.maxWidth);

<<<<<<< HEAD
        return SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MatrixColumnHeaders(tableWidth: tableWidth),
              const SizedBox(height: AppSpacing.space4),
              for (final group in groups) ...[
                _CategoryCard(
                  category: group.category,
                  permissionKeys: group.permissionKeys,
                  matrix: matrix,
                  savedMatrix: savedMatrix,
                  editable: editable,
                  onToggle: onToggle,
                  isCellDirty: isCellDirty,
                  tableWidth: tableWidth,
                ),
                const SizedBox(height: AppSpacing.space4),
              ],
              if (groups.isEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceDefault,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.space6),
                    child: AppEmptyState(
                      title: 'No permissions configured',
                      description: 'Permission keys are not available for this organization.',
                    ),
                  ),
                ),
            ],
=======
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MatrixColumnHeaders(tableWidth: tableWidth),
                const SizedBox(height: AppSpacing.space4),
                for (final group in groups) ...[
                  _CategoryCard(
                    category: group.category,
                    permissionKeys: group.permissionKeys,
                    matrix: matrix,
                    savedMatrix: savedMatrix,
                    editable: editable,
                    onToggle: onToggle,
                    isCellDirty: isCellDirty,
                  ),
                  const SizedBox(height: AppSpacing.space4),
                ],
              ],
            ),
>>>>>>> master
          ),
        );
      },
    );
  }
}

double _matrixTableWidth(double maxWidth) {
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return _kMinMatrixTableWidth;
  }
  return math.max(maxWidth, _kMinMatrixTableWidth);
}

class _MatrixColumnHeaders extends StatelessWidget {
  const _MatrixColumnHeaders({required this.tableWidth});

  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
<<<<<<< HEAD
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Row(
            children: [
              SizedBox(
                width: 192,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
                  child: Text(
                    'Permission',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                  ),
                ),
              ),
              for (final role in PermissionMatrixView.displayRoles) ...[
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.7))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: kRoleAccents[role]?.gradient,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space2,
                            vertical: AppSpacing.space3,
                          ),
                          child: AppTooltip(
                            message: kRoleSummaries[role] ?? '',
                            preferBelow: false,
                            child: Text(
                              PermissionMatrixView.roleLabel(role),
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
=======
      child: SizedBox(
        width: tableWidth,
        child: Row(
          children: [
            SizedBox(
              width: 192,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
                child: Text(
                  'Permission',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                ),
              ),
            ),
            for (final role in PermissionMatrixView.displayRoles) ...[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.7))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: kRoleAccents[role]?.gradient,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space3),
                        child: AppTooltip(
                          message: kRoleSummaries[role] ?? '',
                          preferBelow: false,
                          child: Text(
                            PermissionMatrixView.roleLabel(role),
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
>>>>>>> master
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.permissionKeys,
    required this.matrix,
    required this.savedMatrix,
    required this.editable,
    required this.onToggle,
<<<<<<< HEAD
    required this.tableWidth,
=======
>>>>>>> master
    this.isCellDirty,
  });

  final String category;
  final List<String> permissionKeys;
  final PermissionMatrixView matrix;
  final PermissionMatrixView savedMatrix;
  final bool editable;
  final RoleGrantToggleCallback onToggle;
<<<<<<< HEAD
  final double tableWidth;
=======
>>>>>>> master
  final bool Function(StaffRole role, String permissionKey)? isCellDirty;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space4,
              AppSpacing.space4,
              AppSpacing.space4,
              AppSpacing.space2,
            ),
            child: Text(
              PermissionMatrixView.categoryLabel(category),
              style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
<<<<<<< HEAD
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < permissionKeys.length; index++) ...[
                    if (index > 0) Divider(height: 1, color: colors.borderSubtle),
                    _PermissionRow(
                      permissionKey: permissionKeys[index],
                      matrix: matrix,
                      savedMatrix: savedMatrix,
                      editable: editable,
                      onToggle: onToggle,
                      isCellDirty: isCellDirty,
                    ),
                  ],
                ],
              ),
            ),
=======
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < permissionKeys.length; index++) ...[
                if (index > 0) Divider(height: 1, color: colors.borderSubtle),
                _PermissionRow(
                  permissionKey: permissionKeys[index],
                  matrix: matrix,
                  savedMatrix: savedMatrix,
                  editable: editable,
                  onToggle: onToggle,
                  isCellDirty: isCellDirty,
                ),
              ],
            ],
>>>>>>> master
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permissionKey,
    required this.matrix,
    required this.savedMatrix,
    required this.editable,
    required this.onToggle,
    this.isCellDirty,
  });

  final String permissionKey;
  final PermissionMatrixView matrix;
  final PermissionMatrixView savedMatrix;
  final bool editable;
  final RoleGrantToggleCallback onToggle;
  final bool Function(StaffRole role, String permissionKey)? isCellDirty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        children: [
          SizedBox(
            width: 192,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
              child: Text(PermissionMatrixView.permissionLabel(permissionKey), style: AppTypography.bodySm(context)),
            ),
          ),
          for (final role in PermissionMatrixView.displayRoles)
            Expanded(
              child: Center(
                child: _GrantToggle(
                  role: role,
                  permissionKey: permissionKey,
                  granted: matrix.isGranted(role, permissionKey),
                  dirty:
                      isCellDirty?.call(role, permissionKey) ??
                      matrix.isGranted(role, permissionKey) != savedMatrix.isGranted(role, permissionKey),
                  editable:
                      editable &&
                      canTogglePermissionGrant(
                        role: role,
                        permissionKey: permissionKey,
                        nextGranted: !matrix.isGranted(role, permissionKey),
                      ),
                  onToggle: () => onToggle(role: role, permissionKey: permissionKey),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GrantToggle extends StatelessWidget {
  const _GrantToggle({
    required this.role,
    required this.permissionKey,
    required this.granted,
    required this.dirty,
    required this.editable,
    required this.onToggle,
  });

  final StaffRole role;
  final String permissionKey;
  final bool granted;
  final bool dirty;
  final bool editable;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label =
        '${granted ? 'Revoke' : 'Grant'} ${PermissionMatrixView.permissionLabel(permissionKey)} for ${PermissionMatrixView.roleLabel(role)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: editable ? onToggle : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dirty ? colors.actionPrimary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space1),
            child: Semantics(
              label: label,
              button: true,
              toggled: granted,
              enabled: editable,
              child: _GrantIndicator(granted: granted),
            ),
          ),
        ),
      ),
    );
  }
}

class _GrantIndicator extends StatelessWidget {
  const _GrantIndicator({required this.granted});

  final bool granted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: granted ? colors.actionPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: granted ? null : Border.all(color: colors.borderDefault),
      ),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Icon(
          granted ? Icons.check : Icons.close,
          size: granted ? 13 : 12,
          color: granted ? colors.actionPrimaryFg : colors.iconMuted,
        ),
      ),
    );
  }
}
