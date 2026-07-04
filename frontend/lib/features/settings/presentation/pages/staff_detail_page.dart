import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_permission_action.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Staff member detail and edit page on `/settings/staff/:staffId`.
class StaffDetailPage extends ConsumerStatefulWidget {
  const StaffDetailPage({required this.staffId, super.key});

  final String staffId;

  @override
  ConsumerState<StaffDetailPage> createState() => _StaffDetailPageState();
}

class _StaffDetailPageState extends ConsumerState<StaffDetailPage> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  StaffMemberDetail? _detail;
  var _isLoading = true;
  var _isEditing = false;
  var _isSaving = false;
  var _isTogglingActive = false;
  var _isDeleting = false;
  String? _errorMessage;
  StaffRole? _selectedRole;
  String? _primaryBranchId;
  final Set<String> _selectedBranchIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await ref.read(fetchStaffMemberUseCaseProvider)(widget.staffId);
      if (!mounted) {
        return;
      }

      if (detail == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'That staff member was not found. Refresh the list and try again.';
        });
        return;
      }

      _applyDetail(detail);
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load staff details. Check connectivity and try again.';
      });
    }
  }

  void _applyDetail(StaffMemberDetail detail) {
    _fullNameController.text = detail.fullName;
    _phoneController.text = detail.phone ?? '';
    _selectedRole = detail.role;
    _primaryBranchId = detail.primaryBranchId;
    _selectedBranchIds
      ..clear()
      ..addAll(detail.branchIds);
  }

  Future<void> _save() async {
    final detail = _detail;
    final role = _selectedRole;
    if (detail == null || role == null) {
      return;
    }

    if (_selectedBranchIds.isEmpty) {
      setState(() => _errorMessage = 'Select at least one branch assignment.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(updateStaffMemberUseCaseProvider)(
        UpdateStaffMemberInput(
          staffMemberId: detail.id,
          fullName: _fullNameController.text,
          role: role,
          branchIds: _selectedBranchIds.toList(),
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          primaryBranchId: _primaryBranchId,
        ),
      );

      ref.invalidate(staffListProvider);

      if (!mounted) {
        return;
      }

      await _loadDetail();
      if (!mounted) {
        return;
      }

      setState(() => _isEditing = false);
      ref.showAppToast(message: 'Staff member updated.', variant: AppToastVariant.success);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = staffMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save staff changes. Check connectivity and try again.';
      });
    }
  }

  Future<void> _setActive(bool isActive) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    if (!isActive) {
      final confirmed = await showAppConfirmationDialog(
        context,
        title: 'Deactivate staff member?',
        message:
            '${detail.fullName} will not be able to sign in until reactivated. '
            'Historical records stay linked.',
        confirmLabel: 'Deactivate staff member',
      );
      if (!confirmed) {
        return;
      }
    }

    setState(() => _isTogglingActive = true);

    try {
      await ref.read(setStaffActiveUseCaseProvider)(staffMemberId: detail.id, isActive: isActive);
      ref.invalidate(staffListProvider);

      if (!mounted) {
        return;
      }

      await _loadDetail();
      if (!mounted) {
        return;
      }

      setState(() => _isTogglingActive = false);
      ref.showAppToast(
        message: isActive ? 'Staff member activated.' : 'Staff member deactivated.',
        variant: AppToastVariant.success,
      );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      ref.showAppToast(message: staffMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      ref.showAppToast(
        message: 'Unable to update staff status. Check connectivity and try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  Future<void> _deletePermanently() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete staff member permanently?',
      message:
          'This staff member will be removed from settings and cannot be reactivated. '
          'Historical records linked to them are kept for audit.',
      confirmLabel: 'Delete staff member',
    );
    if (!confirmed) {
      return;
    }

    setState(() => _isDeleting = true);

    try {
      await ref.read(deleteStaffMemberUseCaseProvider)(staffMemberId: detail.id);
      ref.invalidate(staffListProvider);

      if (!mounted) {
        return;
      }

      ref.showAppToast(message: 'Staff member deleted.', variant: AppToastVariant.success);
      context.nav.goSettingsStaff();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(message: staffMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(
        message: 'Unable to delete staff member. Check connectivity and try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canAccess = AuthRouteGuard.canAccessStaffManagement(auth);
    final caller = auth.context?.staffProfile;
    final canResetPassword = caller != null && ProvisioningRules.canResetStaffPassword(caller);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);

    if (!canAccess) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Staff member',
            description: 'You do not have permission to manage staff.',
          ),
        ),
      );
    }

    if (_isLoading) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(child: AppSpinner()),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'Staff member not found',
            description: _errorMessage ?? 'Unable to load staff member.',
            actionLabel: 'Back to staff list',
            onAction: () => context.nav.goSettingsStaff(),
          ),
        ),
      );
    }

    final selectableRoles = caller == null ? const <StaffRole>[] : ProvisioningRules.selectableRoles(caller);
    final roleOptions = [
      for (final role in selectableRoles)
        AppSelectOption<StaffRole>(value: role, label: role.displayLabel),
    ];

    final branchById = branchesAsync.maybeWhen(
      data: (branches) => {for (final branch in branches) branch.id: branch},
      orElse: () => const <String, BranchSummary>{},
    );

    final isBusy = _isSaving || _isTogglingActive || _isDeleting;

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: RecordDetailPattern(
        title: detail.fullName,
        description: detail.role.displayLabel,
        breadcrumb: AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
            AppBreadcrumbItem(label: 'Staff', onTap: () => context.nav.goSettingsStaff()),
            AppBreadcrumbItem(label: detail.fullName),
          ],
        ),
        statusBadge: AppBadge(
          color: detail.isActive ? AppBadgeColor.success : AppBadgeColor.neutral,
          child: Text(detail.isActive ? 'Active' : 'Inactive'),
        ),
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canResetPassword)
              AppButton(
                label: 'Reset password',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                disabled: isBusy,
                onPressed: isBusy ? null : () => context.nav.goSettingsStaffResetPassword(detail.id),
              ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: detail.isActive ? 'Deactivate' : 'Activate',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              loading: _isTogglingActive,
              disabled: isBusy,
              onPressed: isBusy ? null : () => _setActive(!detail.isActive),
            ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: _isEditing ? 'Cancel edit' : 'Edit',
              size: AppButtonSize.sm,
              leadingIcon: _isEditing ? LucideIcons.x : LucideIcons.pencil,
              disabled: isBusy,
              onPressed: isBusy
                  ? null
                  : () {
                      if (_isEditing) {
                        _applyDetail(detail);
                        setState(() {
                          _isEditing = false;
                          _errorMessage = null;
                        });
                      } else {
                        setState(() => _isEditing = true);
                      }
                    },
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
              const SizedBox(height: AppSpacing.s4),
            ],
            if (_isEditing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    label: 'Full name',
                    requiredMark: true,
                    child: AppTextField(
                      controller: _fullNameController,
                      disabled: isBusy,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  AppFormField(
                    label: 'Phone number',
                    child: AppTextField(
                      controller: _phoneController,
                      disabled: isBusy,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  AppFormField(
                    label: 'Role',
                    requiredMark: true,
                    child: AppSelect<StaffRole>(
                      options: roleOptions,
                      value: _selectedRole,
                      disabled: isBusy,
                      onChanged: isBusy ? null : (role) => setState(() => _selectedRole = role),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  AppSectionHeader(title: 'Branch assignments'),
                  const SizedBox(height: AppSpacing.s3),
                  for (final branchId in branchById.keys) ...[
                    AppCheckbox(
                      value: _selectedBranchIds.contains(branchId),
                      label: branchById[branchId]?.name ?? branchId,
                      onChanged: isBusy
                          ? null
                          : (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedBranchIds.add(branchId);
                                  _primaryBranchId ??= branchId;
                                } else {
                                  _selectedBranchIds.remove(branchId);
                                  if (_primaryBranchId == branchId) {
                                    _primaryBranchId = _selectedBranchIds.isEmpty
                                        ? null
                                        : _selectedBranchIds.first;
                                  }
                                }
                              });
                            },
                    ),
                    const SizedBox(height: AppSpacing.s2),
                  ],
                  if (_selectedBranchIds.length > 1) ...[
                    const SizedBox(height: AppSpacing.s4),
                    AppFormField(
                      label: 'Primary branch',
                      child: AppSelect<String>(
                        options: [
                          for (final id in _selectedBranchIds)
                            AppSelectOption<String>(
                              value: id,
                              label: branchById[id]?.name ?? id,
                            ),
                        ],
                        value: _primaryBranchId,
                        disabled: isBusy,
                        onChanged: isBusy ? null : (id) => setState(() => _primaryBranchId = id),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton(
                      label: 'Save changes',
                      loading: _isSaving,
                      onPressed: isBusy ? null : _save,
                    ),
                  ),
                ],
              )
            else
              AppDescriptionList(
                items: [
                  AppDescriptionItem(label: 'Full name', value: Text(detail.fullName)),
                  AppDescriptionItem(label: 'Username', value: Text(detail.username ?? '—')),
                  AppDescriptionItem(label: 'Phone', value: Text(detail.phone ?? '—'), tabular: true),
                  AppDescriptionItem(label: 'Role', value: Text(detail.role.displayLabel)),
                  AppDescriptionItem(
                    label: 'Branches',
                    value: Text(
                      detail.branchIds.isEmpty
                          ? '—'
                          : detail.branchIds
                                .map((id) => branchById[id]?.name ?? id)
                                .join(', '),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.s6),
            SettingsPermissionAction(
              disabledReason: detail.isActive ? 'Deactivate the staff member before deleting them.' : null,
              builder: (enabled) => AppButton(
                label: 'Delete staff member permanently',
                variant: AppButtonVariant.ghost,
                disabled: !enabled || isBusy,
                onPressed: enabled && !isBusy ? _deletePermanently : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
