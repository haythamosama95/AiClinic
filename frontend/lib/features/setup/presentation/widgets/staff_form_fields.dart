import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

/// How [StaffFormFields] validates and presents staff inputs.
enum StaffFormFieldsMode {
  /// Create: standard form fields.
  create,

  /// Edit: all fields editable immediately (e.g. staff detail sheet).
  edit,
}

/// Existing staff values for [StaffFormFieldsMode.edit].
@immutable
class StaffFormExistingData {
  const StaffFormExistingData({this.fullName, this.phone, this.role, this.branchAssignmentLabel});

  final String? fullName;
  final String? phone;
  final StaffRole? role;
  final String? branchAssignmentLabel;
}

/// Shared staff name, phone, role, and branch assignment inputs.
class StaffFormFields extends StatefulWidget {
  const StaffFormFields({
    super.key,
    required this.mode,
    required this.usernameController,
    required this.fullNameController,
    required this.phoneController,
    required this.passwordController,
    this.existing,
    this.enabled = true,
    this.showCredentials = false,
    this.fieldErrors = const {},
    required this.selectableRoles,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.branchIds,
    required this.branchById,
    required this.selectedBranchIds,
    required this.primaryBranchId,
    required this.onBranchChecked,
    required this.onPrimaryBranchChanged,
    this.onBranchesChanged,
    this.branchSelectionControl,
    this.createAction,
    this.showBranchAssignments = true,
  });

  final StaffFormFieldsMode mode;
  final TextEditingController usernameController;
  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final StaffFormExistingData? existing;
  final bool enabled;
  final bool showCredentials;
  final Map<String, String> fieldErrors;
  final List<StaffRole> selectableRoles;
  final StaffRole? selectedRole;
  final ValueChanged<StaffRole?> onRoleChanged;
  final List<String> branchIds;
  final Map<String, BranchSummary> branchById;
  final Set<String> selectedBranchIds;
  final String? primaryBranchId;
  final void Function(String branchId, bool checked) onBranchChecked;
  final ValueChanged<String?> onPrimaryBranchChanged;
  final ValueChanged<Set<String>>? onBranchesChanged;
  final FMultiValueNotifier<String>? branchSelectionControl;
  final Widget? createAction;

  /// When false, branch assignment inputs are hidden (assignment handled by the parent).
  final bool showBranchAssignments;

  static String roleLabel(StaffRole role) => switch (role) {
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };

  @override
  State<StaffFormFields> createState() => _StaffFormFieldsState();
}

class _StaffFormFieldsState extends State<StaffFormFields> {
  var _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == StaffFormFieldsMode.create;
    final roleItems = {for (final role in widget.selectableRoles) StaffFormFields.roleLabel(role): role};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCreate) ...[
          SetupFormGrid(
            children: [
              AppTextField(
                label: 'Full name *',
                controller: widget.fullNameController,
                hintText: 'Enter full name',
                enabled: widget.enabled,
                validator: (value) {
                  final serverError = widget.fieldErrors['fullName'];
                  if (serverError != null) {
                    return serverError;
                  }
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required';
                  }
                  return null;
                },
              ),
              AppTextField(
                label: 'Phone number *',
                controller: widget.phoneController,
                hintText: 'Numbers only',
                enabled: widget.enabled,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: BranchFieldValidation.validatePhone,
              ),
              AppTextField(
                label: 'Username *',
                description: staffUsernameRequirements,
                controller: widget.usernameController,
                hintText: 'Staff username',
                enabled: widget.enabled,
                validator: (value) => validateStaffUsername(value ?? ''),
              ),
              AppTextField(
                label: 'Initial password *',
                description:
                    '${StaffPasswordValidation.initialPasswordRequirements} '
                    'Shown once after creation so you can share it with the staff member.',
                controller: widget.passwordController,
                hintText: '••••••••',
                obscureText: _obscurePassword,
                enabled: widget.enabled,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                validator: StaffPasswordValidation.validateInitialPassword,
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.lg),
          if (widget.showBranchAssignments)
            SetupFormGrid(
              children: [
                AppSelect<StaffRole>(
                  label: 'Role *',
                  items: roleItems,
                  value: widget.selectedRole,
                  hintText: 'Select a role',
                  enabled: widget.enabled && roleItems.isNotEmpty,
                  onChanged: widget.enabled ? widget.onRoleChanged : null,
                  autovalidateMode: AutovalidateMode.disabled,
                  validator: (value) => value == null ? 'Select a role' : null,
                ),
                _BranchAssignmentsMultiSelect(
                  branchIds: widget.branchIds,
                  branchById: widget.branchById,
                  selectedBranchIds: widget.selectedBranchIds,
                  primaryBranchId: widget.primaryBranchId,
                  enabled: widget.enabled,
                  selectionControl: widget.branchSelectionControl,
                  onBranchesChanged: widget.onBranchesChanged,
                  onPrimaryBranchChanged: widget.onPrimaryBranchChanged,
                ),
              ],
            )
          else
            AppSelect<StaffRole>(
              label: 'Role *',
              items: roleItems,
              value: widget.selectedRole,
              hintText: 'Select a role',
              enabled: widget.enabled && roleItems.isNotEmpty,
              onChanged: widget.enabled ? widget.onRoleChanged : null,
              autovalidateMode: AutovalidateMode.disabled,
              validator: (value) => value == null ? 'Select a role' : null,
            ),
          if (widget.createAction != null) ...[
            const SizedBox(height: SpacingTokens.lg),
            Align(alignment: Alignment.centerRight, child: widget.createAction!),
          ],
        ],
        if (!isCreate) ...[
          AppTextField(
            label: 'Full name *',
            controller: widget.fullNameController,
            hintText: 'Enter full name',
            enabled: widget.enabled,
            validator: (value) {
              final serverError = widget.fieldErrors['fullName'];
              if (serverError != null) {
                return serverError;
              }
              if (value == null || value.trim().isEmpty) {
                return 'Full name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: SpacingTokens.lg),
          AppTextField(
            label: 'Phone (optional)',
            controller: widget.phoneController,
            hintText: 'Numbers only',
            enabled: widget.enabled,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return null;
              }
              return BranchFieldValidation.validatePhone(value);
            },
          ),
          const SizedBox(height: SpacingTokens.lg),
          AppSelect<StaffRole>(
            label: 'Role *',
            items: roleItems,
            value: widget.selectedRole,
            hintText: 'Select a role',
            enabled: widget.enabled && roleItems.isNotEmpty,
            onChanged: widget.enabled ? widget.onRoleChanged : null,
            autovalidateMode: AutovalidateMode.disabled,
            validator: (value) => value == null ? 'Select a role' : null,
          ),
          const SizedBox(height: SpacingTokens.lg),
          _BranchAssignmentsEditor(
            branchIds: widget.branchIds,
            branchById: widget.branchById,
            selectedBranchIds: widget.selectedBranchIds,
            primaryBranchId: widget.primaryBranchId,
            enabled: widget.enabled,
            onBranchChecked: widget.onBranchChecked,
            onPrimaryBranchChanged: widget.onPrimaryBranchChanged,
          ),
          if (widget.showCredentials) ...[
            const SizedBox(height: SpacingTokens.xl),
            Text('Login credentials', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: SpacingTokens.md),
            AppTextField(
              label: 'Username *',
              description: staffUsernameRequirements,
              controller: widget.usernameController,
              hintText: 'Staff username',
              enabled: widget.enabled,
              validator: (value) => validateStaffUsername(value ?? ''),
            ),
            const SizedBox(height: SpacingTokens.lg),
            AppTextField(
              label: 'New password',
              description:
                  '${StaffPasswordValidation.initialPasswordRequirements} '
                  'Leave blank to keep the current password.',
              controller: widget.passwordController,
              hintText: '••••••••',
              obscureText: _obscurePassword,
              enabled: widget.enabled,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              validator: StaffPasswordValidation.validateOptionalPassword,
            ),
          ],
        ],
      ],
    );
  }
}

class _BranchAssignmentsMultiSelect extends StatelessWidget {
  const _BranchAssignmentsMultiSelect({
    required this.branchIds,
    required this.branchById,
    required this.selectedBranchIds,
    required this.primaryBranchId,
    required this.enabled,
    this.selectionControl,
    required this.onBranchesChanged,
    required this.onPrimaryBranchChanged,
  });

  final List<String> branchIds;
  final Map<String, BranchSummary> branchById;
  final Set<String> selectedBranchIds;
  final String? primaryBranchId;
  final bool enabled;
  final FMultiValueNotifier<String>? selectionControl;
  final ValueChanged<Set<String>>? onBranchesChanged;
  final ValueChanged<String?> onPrimaryBranchChanged;

  @override
  Widget build(BuildContext context) {
    if (branchIds.isEmpty) {
      return Text(
        'No active branches are available. Create or reactivate a branch first.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final items = {for (final branchId in branchIds) _branchLabel(branchId, branchById[branchId]): branchId};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppMultiSelect<String>(
          label: 'Branch assignments *',
          items: items,
          values: selectionControl?.value ?? selectedBranchIds,
          hintText: 'Select branches',
          enabled: enabled,
          control: selectionControl == null
              ? null
              : FMultiValueControl.managed(controller: selectionControl, onChange: onBranchesChanged),
          onChanged: onBranchesChanged,
          autovalidateMode: AutovalidateMode.disabled,
          validator: (values) => values == null || values.isEmpty ? 'Select at least one branch assignment' : null,
        ),
        if (selectedBranchIds.length > 1) ...[
          const SizedBox(height: SpacingTokens.md),
          AppSelect<String>(
            label: 'Primary branch',
            items: {for (final id in selectedBranchIds) branchById[id]?.name ?? 'Branch $id': id},
            value: primaryBranchId,
            enabled: enabled,
            onChanged: onPrimaryBranchChanged,
          ),
        ],
      ],
    );
  }
}

String _branchLabel(String branchId, BranchSummary? branch) {
  if (branch == null) {
    return 'Branch $branchId';
  }
  return '${branch.name}${branch.code == null ? '' : ' (${branch.code})'}';
}

class _BranchAssignmentsEditor extends StatelessWidget {
  const _BranchAssignmentsEditor({
    required this.branchIds,
    required this.branchById,
    required this.selectedBranchIds,
    required this.primaryBranchId,
    required this.enabled,
    required this.onBranchChecked,
    required this.onPrimaryBranchChanged,
  });

  final List<String> branchIds;
  final Map<String, BranchSummary> branchById;
  final Set<String> selectedBranchIds;
  final String? primaryBranchId;
  final bool enabled;
  final void Function(String branchId, bool checked) onBranchChecked;
  final ValueChanged<String?> onPrimaryBranchChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Branch assignments *', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.sm),
        if (branchIds.isEmpty)
          Text(
            'No active branches are available. Create or reactivate a branch first.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...branchIds.map((branchId) {
            final label = _branchLabel(branchId, branchById[branchId]);
            return AppCheckbox(
              value: selectedBranchIds.contains(branchId),
              label: label,
              description: 'Staff can work at this location',
              enabled: enabled,
              onChanged: (checked) => onBranchChecked(branchId, checked),
            );
          }),
        if (selectedBranchIds.length > 1) ...[
          const SizedBox(height: SpacingTokens.md),
          AppSelect<String>(
            label: 'Primary branch',
            items: {for (final id in selectedBranchIds) branchById[id]?.name ?? 'Branch $id': id},
            value: primaryBranchId,
            enabled: enabled,
            onChanged: onPrimaryBranchChanged,
          ),
        ],
      ],
    );
  }
}
