import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_permission_action.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/bootstrap_step_fields.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/branch_working_hours_editor.dart';

/// Edit branch form on `/settings/branches/:branchId/edit`.
class BranchEditPage extends ConsumerStatefulWidget {
  const BranchEditPage({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<BranchEditPage> createState() => _BranchEditPageState();
}

class _BranchEditPageState extends ConsumerState<BranchEditPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mapsUrlController = TextEditingController();

  BranchListItem? _branch;
  BranchWorkingSchedule _workingSchedule = BranchWorkingSchedule.defaultSchedule();
  var _isEditing = false;
  var _isSaving = false;
  var _isTogglingActive = false;
  var _isDeleting = false;
  String? _errorMessage;
  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  void _applyBranch(BranchListItem branch) {
    _nameController.text = branch.name;
    _codeController.text = branch.code ?? '';
    _addressController.text = branch.address ?? '';
    _phoneController.text = branch.phone ?? '';
    _mapsUrlController.text = branch.mapsUrl ?? '';
    _workingSchedule = branch.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
    _branch = branch;
  }

  Future<void> _openWorkingHours() async {
    final updated = await showBranchWorkingHoursEditor(context, initialSchedule: _workingSchedule);
    if (updated == null || !mounted) {
      return;
    }
    setState(() => _workingSchedule = updated);
    await _saveWorkingHours(updated);
  }

  Future<void> _saveWorkingHours(BranchWorkingSchedule schedule) async {
    final branch = _branch;
    if (branch == null) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ref.read(updateBranchUseCaseProvider)(
        UpdateBranchInput(
          branchId: branch.id,
          name: branch.name,
          workingSchedule: schedule,
          code: branch.code,
          address: branch.address,
          phone: branch.phone,
          mapsUrl: branch.mapsUrl,
        ),
      );

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isSaving = false);
      ref.showAppToast(message: 'Working hours updated.', variant: AppToastVariant.success);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ref.showAppToast(message: branchMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ref.showAppToast(
        message: 'Unable to save working hours. Check connectivity and try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  Future<void> _save() async {
    final branch = _branch;
    if (branch == null) {
      return;
    }

    final errors = BootstrapBranchStepFields.validate(
      branchName: _nameController.text,
      branchCode: _codeController.text,
      address: _addressController.text,
      phone: _phoneController.text,
      mapsUrl: _mapsUrlController.text,
      workingSchedule: _workingSchedule,
    );
    setState(() => _fieldErrors.addAll(errors));
    if (errors.values.any((error) => error != null)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(updateBranchUseCaseProvider)(
        UpdateBranchInput(
          branchId: branch.id,
          name: _nameController.text,
          workingSchedule: _workingSchedule,
          code: _codeController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          mapsUrl: _mapsUrlController.text,
        ),
      );

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ref.showAppToast(message: 'Branch updated.', variant: AppToastVariant.success);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = branchMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save branch. Check connectivity and try again.';
      });
    }
  }

  Future<void> _setActive(bool isActive) async {
    final branch = _branch;
    if (branch == null) {
      return;
    }

    if (!isActive) {
      final confirmed = await showAppConfirmationDialog(
        context,
        title: 'Deactivate branch?',
        message:
            'This branch will be hidden from pickers and new assignments. '
            'Historical records stay linked. You can reactivate it later.',
        confirmLabel: 'Deactivate branch',
      );
      if (!confirmed) {
        return;
      }
    }

    setState(() => _isTogglingActive = true);

    try {
      await ref.read(setBranchActiveUseCaseProvider)(branchId: branch.id, isActive: isActive);
      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isTogglingActive = false);
      ref.showAppToast(
        message: isActive ? 'Branch activated.' : 'Branch deactivated.',
        variant: AppToastVariant.success,
      );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      ref.showAppToast(message: branchMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      ref.showAppToast(
        message: 'Unable to update branch status. Check connectivity and try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  Future<void> _deletePermanently() async {
    final branch = _branch;
    if (branch == null) {
      return;
    }

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete branch permanently?',
      message:
          'This branch will be removed from settings and cannot be reactivated. '
          'Historical records linked to this branch are kept for audit.',
      confirmLabel: 'Delete branch',
    );
    if (!confirmed) {
      return;
    }

    setState(() => _isDeleting = true);

    try {
      await ref.read(deleteBranchUseCaseProvider)(branchId: branch.id);
      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      ref.showAppToast(message: 'Branch deleted.', variant: AppToastVariant.success);
      context.nav.goSettingsBranches();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(message: branchMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(
        message: 'Unable to delete branch. Check connectivity and try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canManage = AuthRouteGuard.canAccessBranchManagement(auth);
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    if (!canManage) {
      return ColoredBox(
        color: context.colors.surfaceCanvas,
        child: const Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Edit branch',
            description: 'You do not have permission to manage branches.',
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: branchesAsync.when(
        loading: () => const Center(child: AppSpinner()),
        error: (error, _) => Center(
          child: AppErrorState(
            message: 'Failed to load branch: $error',
            onRetry: () => ref.invalidate(clinicSetupBranchesProvider),
          ),
        ),
        data: (branches) {
          final branch = branches.cast<BranchListItem?>().firstWhere(
            (item) => item?.id == widget.branchId,
            orElse: () => null,
          );

          if (branch == null) {
            return const Center(
              child: AppEmptyState(
                variant: AppEmptyStateVariant.error,
                title: 'Branch not found',
                description: 'That branch was not found. Refresh the list and try again.',
              ),
            );
          }

          if (_branch?.id != branch.id) {
            _applyBranch(branch);
          } else if (!_isEditing) {
            _applyBranch(branch);
          }

          final isBusy = _isSaving || _isTogglingActive || _isDeleting;

          return EditorFormPattern(
            title: branch.name,
            description: branch.isActive ? 'Active branch' : 'Inactive branch',
            breadcrumb: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: 'Settings', onTap: () => context.nav.goSettings()),
                AppBreadcrumbItem(label: 'Branches', onTap: () => context.nav.goSettingsBranches()),
                AppBreadcrumbItem(label: branch.name),
              ],
            ),
            headerActions: _isEditing
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: branch.isActive ? 'Deactivate' : 'Activate',
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.sm,
                        loading: _isTogglingActive,
                        disabled: isBusy,
                        onPressed: isBusy ? null : () => _setActive(!branch.isActive),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      AppButton(
                        label: 'Edit',
                        size: AppButtonSize.sm,
                        leadingIcon: LucideIcons.pencil,
                        disabled: isBusy,
                        onPressed: isBusy ? null : () => setState(() => _isEditing = true),
                      ),
                    ],
                  ),
            summaryAlert: _errorMessage == null
                ? null
                : AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
            sections: [
              EditorFormSection(
                title: 'Branch details',
                fields: [
                  if (_isEditing)
                    BootstrapBranchStepFields(
                      nameController: _nameController,
                      codeController: _codeController,
                      addressController: _addressController,
                      phoneController: _phoneController,
                      mapsUrlController: _mapsUrlController,
                      workingSchedule: _workingSchedule,
                      onWorkingScheduleChanged: (schedule) => setState(() => _workingSchedule = schedule),
                      fieldErrors: _fieldErrors,
                      onFieldBlur: (_) {},
                      disabled: isBusy,
                    )
                  else
                    AppDescriptionList(
                      items: [
                        AppDescriptionItem(label: 'Branch name', value: Text(branch.name)),
                        AppDescriptionItem(label: 'Code', value: Text(branch.code ?? '—')),
                        AppDescriptionItem(label: 'Address', value: Text(branch.address ?? '—')),
                        AppDescriptionItem(
                          label: 'Phone',
                          value: Text(branch.phone ?? '—'),
                          tabular: true,
                        ),
                        AppDescriptionItem(label: 'Maps URL', value: Text(branch.mapsUrl ?? '—')),
                      ],
                    ),
                ],
              ),
              if (!_isEditing)
                EditorFormSection(
                  title: 'Working hours',
                  fields: [
                    AppButton(
                      label: _workingSchedule.hasConfiguredWorkingHours
                          ? 'Working hours configured'
                          : 'Configure working hours',
                      variant: AppButtonVariant.secondary,
                      leadingIcon: LucideIcons.clock,
                      disabled: isBusy,
                      onPressed: isBusy ? null : _openWorkingHours,
                    ),
                  ],
                ),
            ],
            trailingContent: !_isEditing
                ? SettingsPermissionAction(
                    disabledReason: branch.isActive
                        ? 'Deactivate the branch before deleting it.'
                        : null,
                    builder: (enabled) => AppButton(
                      label: 'Delete branch permanently',
                      variant: AppButtonVariant.ghost,
                      disabled: !enabled || isBusy,
                      onPressed: enabled && !isBusy ? _deletePermanently : null,
                    ),
                  )
                : null,
            footer: _isEditing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        disabled: isBusy,
                        onPressed: () {
                          _applyBranch(branch);
                          setState(() {
                            _isEditing = false;
                            _errorMessage = null;
                            _fieldErrors.clear();
                          });
                        },
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      AppButton(label: 'Save', loading: _isSaving, onPressed: _save),
                    ],
                  )
                : AppButton(
                    label: 'Back to branches',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.nav.goSettingsBranches(),
                  ),
          );
        },
      ),
    );
  }
}
