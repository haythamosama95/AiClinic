import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_working_hours_sheet.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/branch_form_fields.dart';

/// Single branch card for clinic setup settings.
class BranchSettingsSection extends ConsumerStatefulWidget {
  const BranchSettingsSection({required this.branch, super.key});

  final BranchListItem branch;

  @override
  ConsumerState<BranchSettingsSection> createState() => _BranchSettingsSectionState();
}

class _BranchSettingsSectionState extends ConsumerState<BranchSettingsSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _mapsUrlController;
  var _isEditing = false;
  var _isSaving = false;
  var _isSavingWorkingHours = false;
  var _isTogglingActive = false;
  var _isDeletingBranch = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
    _addressController = TextEditingController();
    _phoneController = TextEditingController();
    _mapsUrlController = TextEditingController();
    _applyBranch(widget.branch);
  }

  @override
  void didUpdateWidget(covariant BranchSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branch != widget.branch && !_isEditing) {
      _applyBranch(widget.branch);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  BranchWorkingSchedule get _persistedWorkingSchedule =>
      widget.branch.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();

  void _applyBranch(BranchListItem branch) {
    _nameController.text = branch.name;
    _codeController.text = branch.code ?? '';
    _addressController.text = branch.address ?? '';
    _phoneController.text = branch.phone ?? '';
    _mapsUrlController.text = branch.mapsUrl ?? '';
  }

  BranchFormExistingData get _existingData => BranchFormExistingData(
    name: widget.branch.name,
    code: widget.branch.code,
    address: widget.branch.address,
    phone: widget.branch.phone,
    mapsUrl: widget.branch.mapsUrl,
    workingSchedule: _persistedWorkingSchedule,
  );

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _errorMessage = null;
    });
  }

  void _cancelEditing() {
    _applyBranch(widget.branch);
    setState(() {
      _isEditing = false;
      _errorMessage = null;
    });
  }

  Future<void> _openWorkingHoursSheet() async {
    await AppSheets.showModal<void>(
      context: context,
      side: AppSheetSide.right,
      width: 520,
      builder: (context) =>
          BranchWorkingHoursSheet(initialSchedule: _persistedWorkingSchedule, onUpdate: _saveWorkingHours),
    );
  }

  Future<void> _saveWorkingHours(BranchWorkingSchedule schedule) async {
    setState(() => _isSavingWorkingHours = true);

    try {
      await ref.read(updateBranchUseCaseProvider)(
        UpdateBranchInput(
          branchId: widget.branch.id,
          name: widget.branch.name,
          workingSchedule: schedule,
          code: widget.branch.code,
          address: widget.branch.address,
          phone: widget.branch.phone,
          mapsUrl: widget.branch.mapsUrl,
        ),
      );

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isSavingWorkingHours = false);
      AppToast.success(context, message: 'Working hours updated.');
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSavingWorkingHours = false);
      AppToast.error(context, message: branchMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSavingWorkingHours = false);
      AppToast.error(context, message: 'Unable to save working hours. Check connectivity and try again.');
    }
  }

  Future<void> _confirmDelete() async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Deactivate branch?',
      message:
          'This branch will be hidden from pickers and new assignments. '
          'Historical records stay linked. You can reactivate it later.',
      confirmLabel: 'Deactivate branch',
      cancelLabel: 'Cancel',
      destructive: true,
      onConfirm: _delete,
    );
  }

  Future<void> _delete() async {
    setState(() => _isTogglingActive = true);

    try {
      await ref.read(setBranchActiveUseCaseProvider)(branchId: widget.branch.id, isActive: false);

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isTogglingActive = false);
      AppToast.success(context, message: 'Branch deactivated.');
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      AppToast.error(context, message: branchMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      AppToast.error(context, message: 'Unable to deactivate branch. Check connectivity and try again.');
    }
  }

  Future<void> _activate() async {
    setState(() => _isTogglingActive = true);

    try {
      await ref.read(setBranchActiveUseCaseProvider)(branchId: widget.branch.id, isActive: true);

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isTogglingActive = false);
      AppToast.success(context, message: 'Branch activated.');
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      AppToast.error(context, message: branchMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isTogglingActive = false);
      AppToast.error(context, message: 'Unable to activate branch. Check connectivity and try again.');
    }
  }

  Future<void> _confirmPermanentDelete() async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Delete branch permanently?',
      message:
          'This branch will be removed from settings and cannot be reactivated. '
          'Historical records linked to this branch are kept for audit.',
      confirmLabel: 'Delete branch',
      cancelLabel: 'Cancel',
      destructive: true,
      onConfirm: _permanentlyDelete,
    );
  }

  Future<void> _permanentlyDelete() async {
    setState(() => _isDeletingBranch = true);

    try {
      await ref.read(deleteBranchUseCaseProvider)(branchId: widget.branch.id);

      ref.invalidate(clinicSetupBranchesProvider);

      if (!mounted) {
        return;
      }

      setState(() => _isDeletingBranch = false);
      AppToast.success(context, message: 'Branch deleted.');
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeletingBranch = false);
      AppToast.error(context, message: branchMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeletingBranch = false);
      AppToast.error(context, message: 'Unable to delete branch. Check connectivity and try again.');
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(updateBranchUseCaseProvider)(
        UpdateBranchInput(
          branchId: widget.branch.id,
          name: _nameController.text,
          workingSchedule: _persistedWorkingSchedule,
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
      AppToast.success(context, message: 'Branch updated.');
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
        _errorMessage = 'Unable to save branch settings. Check connectivity and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.branch.code == null || widget.branch.code!.isEmpty
        ? widget.branch.name
        : '${widget.branch.name} (${widget.branch.code})';

    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BranchSettingsHeaderBar(
            title: title,
            isActive: widget.branch.isActive,
            isEditing: _isEditing,
            isSaving: _isSaving,
            isSavingWorkingHours: _isSavingWorkingHours,
            isTogglingActive: _isTogglingActive,
            isDeletingBranch: _isDeletingBranch,
            onWorkingHours: _openWorkingHoursSheet,
            onEdit: _startEditing,
            onDelete: _confirmDelete,
            onPermanentDelete: _confirmPermanentDelete,
            onActivate: _activate,
            onSave: _save,
            onCancel: _cancelEditing,
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
                    const SizedBox(height: SpacingTokens.lg),
                  ],
                  BranchFormFields(
                    mode: BranchFormFieldsMode.edit,
                    isEditing: _isEditing,
                    existing: _existingData,
                    nameController: _nameController,
                    codeController: _codeController,
                    addressController: _addressController,
                    phoneController: _phoneController,
                    mapsUrlController: _mapsUrlController,
                    enabled: !_isSaving && !_isSavingWorkingHours,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSettingsHeaderBar extends StatelessWidget {
  const _BranchSettingsHeaderBar({
    required this.title,
    required this.isActive,
    required this.isEditing,
    required this.isSaving,
    required this.isSavingWorkingHours,
    required this.isTogglingActive,
    required this.isDeletingBranch,
    required this.onWorkingHours,
    required this.onEdit,
    required this.onDelete,
    required this.onPermanentDelete,
    required this.onActivate,
    required this.onSave,
    required this.onCancel,
  });

  final String title;
  final bool isActive;
  final bool isEditing;
  final bool isSaving;
  final bool isSavingWorkingHours;
  final bool isTogglingActive;
  final bool isDeletingBranch;
  final VoidCallback onWorkingHours;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPermanentDelete;
  final Future<void> Function() onActivate;
  final Future<void> Function() onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600);
    final titleRow = _BranchTitleRow(title: title, isActive: isActive, style: titleStyle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = constraints.maxWidth < 420;

          if (stackActions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow,
                const SizedBox(height: SpacingTokens.sm),
                Align(alignment: Alignment.centerRight, child: _buildActions(context, colors, compact: true)),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleRow),
              _buildActions(context, colors, compact: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActions(BuildContext context, SemanticColors colors, {required bool compact}) {
    final actionsLocked = isSaving || isSavingWorkingHours || isTogglingActive || isDeletingBranch;

    final workingHoursAction = compact
        ? IconButton(
            tooltip: 'Working hours',
            onPressed: actionsLocked ? null : onWorkingHours,
            icon: isSavingWorkingHours
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.mutedForeground),
                  )
                : Icon(Icons.schedule_outlined, color: colors.mutedForeground),
          )
        : AppButton(
            label: 'Working hours',
            variant: AppButtonVariant.outline,
            expand: false,
            icon: const Icon(Icons.schedule_outlined, size: 18),
            isLoading: isSavingWorkingHours,
            onPressed: actionsLocked ? null : onWorkingHours,
          );

    final togglingIndicator = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: isActive ? colors.destructive : colors.primary),
    );

    final deletingIndicator = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: colors.destructive),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        workingHoursAction,
        if (!compact) const SizedBox(width: SpacingTokens.sm),
        if (isEditing) ...[
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            expand: false,
            onPressed: isSaving ? null : onCancel,
          ),
          const SizedBox(width: SpacingTokens.sm),
          AppButton(label: 'Save', expand: false, isLoading: isSaving, onPressed: isSaving ? null : onSave),
        ] else ...[
          IconButton(
            tooltip: 'Edit',
            onPressed: actionsLocked ? null : onEdit,
            icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
          ),
          if (isActive)
            IconButton(
              tooltip: 'Deactivate branch',
              onPressed: actionsLocked ? null : onDelete,
              icon: isTogglingActive ? togglingIndicator : Icon(Icons.delete_outline, color: colors.destructive),
            )
          else ...[
            IconButton(
              tooltip: 'Activate branch',
              onPressed: actionsLocked ? null : onActivate,
              icon: isTogglingActive ? togglingIndicator : Icon(Icons.play_circle_outline, color: colors.primary),
            ),
            IconButton(
              tooltip: 'Delete branch permanently',
              onPressed: actionsLocked ? null : onPermanentDelete,
              icon: isDeletingBranch
                  ? deletingIndicator
                  : Icon(Icons.delete_forever_outlined, color: colors.destructive),
            ),
          ],
        ],
      ],
    );
  }
}

class _BranchTitleRow extends StatelessWidget {
  const _BranchTitleRow({required this.title, required this.isActive, required this.style});

  final String title;
  final bool isActive;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final statusIcon = isActive
        ? Icon(Icons.check_circle_outline, size: 20, color: colors.primary)
        : Icon(Icons.pause_circle_outline, size: 20, color: colors.mutedForeground);

    return Row(
      children: [
        Tooltip(message: isActive ? 'Active branch' : 'Inactive branch', child: statusIcon),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(child: Text(title, style: style)),
      ],
    );
  }
}
