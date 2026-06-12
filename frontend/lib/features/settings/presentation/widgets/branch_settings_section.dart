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
            isEditing: _isEditing,
            isSaving: _isSaving,
            isSavingWorkingHours: _isSavingWorkingHours,
            onWorkingHours: _openWorkingHoursSheet,
            onEdit: _startEditing,
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
                  if (!widget.branch.isActive) ...[
                    AppAlert(title: 'This branch is inactive.'),
                    const SizedBox(height: SpacingTokens.lg),
                  ],
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
    required this.isEditing,
    required this.isSaving,
    required this.isSavingWorkingHours,
    required this.onWorkingHours,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  final String title;
  final bool isEditing;
  final bool isSaving;
  final bool isSavingWorkingHours;
  final VoidCallback onWorkingHours;
  final VoidCallback onEdit;
  final Future<void> Function() onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
            ),
          ),
          AppButton(
            label: 'Working hours',
            variant: AppButtonVariant.outline,
            expand: false,
            isLoading: isSavingWorkingHours,
            onPressed: isSaving || isSavingWorkingHours ? null : onWorkingHours,
          ),
          const SizedBox(width: SpacingTokens.sm),
          if (isEditing) ...[
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: isSaving ? null : onCancel,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(label: 'Save', expand: false, isLoading: isSaving, onPressed: isSaving ? null : onSave),
          ] else
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
            ),
        ],
      ),
    );
  }
}
