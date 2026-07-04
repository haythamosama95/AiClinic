import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/setup_wizard_draft_ids.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Staff step inputs for the bootstrap wizard (draft list, not live RPC).
class BootstrapStaffStepFields extends ConsumerStatefulWidget {
  const BootstrapStaffStepFields({
    required this.usernameController,
    required this.fullNameController,
    required this.phoneController,
    required this.passwordController,
    required this.wizardBranch,
    required this.staffDrafts,
    required this.fieldErrors,
    required this.onFieldBlur,
    required this.onAddDraft,
    required this.disabled,
    super.key,
  });

  final TextEditingController usernameController;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final BranchSummary? wizardBranch;
  final List<SetupStaffDraft> staffDrafts;
  final Map<String, String?> fieldErrors;
  final void Function(String field) onFieldBlur;
  final Future<void> Function({
    required StaffRole role,
    required List<String> branchIds,
    String? primaryBranchId,
    String? phone,
  })
  onAddDraft;
  final bool disabled;

  @override
  ConsumerState<BootstrapStaffStepFields> createState() => _BootstrapStaffStepFieldsState();
}

class _BootstrapStaffStepFieldsState extends ConsumerState<BootstrapStaffStepFields> {
  StaffRole? _selectedRole;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider).context;
    final caller = auth?.staffProfile;
    final selectableRoles = caller == null ? const <StaffRole>[] : ProvisioningRules.selectableRoles(caller);
    final roleOptions = [
      for (final role in selectableRoles)
        AppSelectOption<StaffRole>(value: role, label: role.displayLabel),
    ];

    if (_selectedRole != null && !selectableRoles.contains(_selectedRole)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedRole = null);
      });
    } else if (_selectedRole == null && selectableRoles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final defaultRole = caller != null &&
                caller.isBootstrapAdmin &&
                selectableRoles.contains(StaffRole.administrator)
            ? StaffRole.administrator
            : selectableRoles.first;
        setState(() => _selectedRole = defaultRole);
      });
    }

    final branch = widget.wizardBranch;
    final branchIds = branch == null ? const <String>[] : [SetupWizardDraftIds.branch];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.staffDrafts.isNotEmpty) ...[
          AppAlert(
            variant: AppAlertVariant.success,
            title: '${widget.staffDrafts.length} staff account${widget.staffDrafts.length == 1 ? '' : 's'} ready to create',
            body: 'Accounts are saved when you click Finish. Add more below or continue.',
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final draft in widget.staffDrafts)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
              child: Text(
                '${draft.fullName} (${draft.username}) — ${draft.role.displayLabel}',
                style: context.typography.body.copyWith(color: context.colors.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.s4),
        ],
        AppFormField(
          label: 'Full name',
          requiredMark: true,
          error: widget.fieldErrors['fullName'],
          child: AppTextField(
            controller: widget.fullNameController,
            hintText: 'Enter full name',
            disabled: widget.disabled,
            invalid: widget.fieldErrors['fullName'] != null,
            onChanged: (_) => widget.onFieldBlur('fullName'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Phone number',
          requiredMark: true,
          error: widget.fieldErrors['phone'],
          child: AppTextField(
            controller: widget.phoneController,
            hintText: 'Numbers only',
            disabled: widget.disabled,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            invalid: widget.fieldErrors['phone'] != null,
            onChanged: (_) => widget.onFieldBlur('phone'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Username',
          requiredMark: true,
          helperText: staffUsernameRequirements,
          error: widget.fieldErrors['username'],
          child: AppTextField(
            controller: widget.usernameController,
            hintText: 'Staff username',
            disabled: widget.disabled,
            invalid: widget.fieldErrors['username'] != null,
            onChanged: (_) => widget.onFieldBlur('username'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Initial password',
          requiredMark: true,
          helperText:
              '${StaffPasswordValidation.initialPasswordRequirements} '
              'Shown once after creation so you can share it with the staff member.',
          error: widget.fieldErrors['password'],
          child: AppPasswordField(
            controller: widget.passwordController,
            hintText: '••••••••',
            disabled: widget.disabled,
            invalid: widget.fieldErrors['password'] != null,
            onChanged: (_) => widget.onFieldBlur('password'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Role',
          requiredMark: true,
          error: widget.fieldErrors['role'],
          child: AppSelect<StaffRole>(
            options: roleOptions,
            value: _selectedRole,
            placeholder: 'Select a role',
            disabled: widget.disabled || roleOptions.isEmpty,
            invalid: widget.fieldErrors['role'] != null,
            onChanged: widget.disabled
                ? null
                : (role) {
                    setState(() => _selectedRole = role);
                    widget.onFieldBlur('role');
                  },
          ),
        ),
        if (branch != null) ...[
          const SizedBox(height: AppSpacing.s4),
          AppFormField(
            label: 'Branch assignment',
            helperText: 'Staff can work at this location.',
            child: Text(
              branch.name,
              style: context.typography.bodyStrong.copyWith(color: context.colors.textPrimary),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Add staff account to setup list',
            variant: AppButtonVariant.secondary,
            loading: widget.disabled,
            disabled: widget.disabled || branchIds.isEmpty || _selectedRole == null,
            onPressed: widget.disabled || branchIds.isEmpty || _selectedRole == null
                ? null
                : () => _submitDraft(branchIds),
          ),
        ),
      ],
    );
  }

  Future<void> _submitDraft(List<String> branchIds) async {
    final role = _selectedRole;
    if (role == null) {
      return;
    }

    final errors = _validateForm(role);
    if (errors.values.any((error) => error != null)) {
      widget.onFieldBlur('submit');
      return;
    }

    await widget.onAddDraft(
      role: role,
      branchIds: branchIds,
      primaryBranchId: branchIds.first,
      phone: widget.phoneController.text.trim().isEmpty ? null : widget.phoneController.text.trim(),
    );
  }

  Map<String, String?> _validateForm(StaffRole role) {
    return {
      'fullName': widget.fullNameController.text.trim().isEmpty ? 'Enter the staff member full name.' : null,
      'phone': BranchFieldValidation.validatePhone(widget.phoneController.text),
      'username': validateStaffUsername(widget.usernameController.text),
      'password': StaffPasswordValidation.validateInitialPassword(widget.passwordController.text),
      'role': ProvisioningRules.validateRoleChoice(
        ref.read(authSessionProvider).context!.staffProfile,
        role,
      ),
    };
  }

}
