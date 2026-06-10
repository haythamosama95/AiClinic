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

  /// Edit: read-only values with **Modify** before editing.
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
    final isEdit = widget.mode == StaffFormFieldsMode.edit;
    final isCreate = widget.mode == StaffFormFieldsMode.create;
    final roleItems = {for (final role in widget.selectableRoles) StaffFormFields.roleLabel(role): role};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCreate) ...[
          SetupFormGrid(
            children: [
              _textField(
                isEdit: false,
                label: 'Full name *',
                currentValue: null,
                controller: widget.fullNameController,
                hintText: 'Enter full name',
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
              _textField(
                isEdit: false,
                label: 'Phone number *',
                currentValue: null,
                controller: widget.phoneController,
                hintText: 'Numbers only',
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
          _textField(
            isEdit: isEdit,
            label: 'Full name *',
            currentValue: widget.existing?.fullName,
            controller: widget.fullNameController,
            hintText: 'Enter full name',
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
          _textField(
            isEdit: isEdit,
            label: 'Phone (optional)',
            currentValue: widget.existing?.phone,
            controller: widget.phoneController,
            hintText: 'Numbers only',
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
          if (isEdit)
            _ModifiableRoleField(
              currentRole: widget.existing?.role,
              selectableRoles: widget.selectableRoles,
              selectedRole: widget.selectedRole,
              enabled: widget.enabled,
              onRoleChanged: widget.onRoleChanged,
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
          const SizedBox(height: SpacingTokens.lg),
          if (isEdit)
            _ModifiableBranchAssignmentsField(
              currentLabel: widget.existing?.branchAssignmentLabel,
              branchIds: widget.branchIds,
              branchById: widget.branchById,
              selectedBranchIds: widget.selectedBranchIds,
              primaryBranchId: widget.primaryBranchId,
              enabled: widget.enabled,
              onBranchChecked: widget.onBranchChecked,
              onPrimaryBranchChanged: widget.onPrimaryBranchChanged,
            )
          else
            _BranchAssignmentsEditor(
              branchIds: widget.branchIds,
              branchById: widget.branchById,
              selectedBranchIds: widget.selectedBranchIds,
              primaryBranchId: widget.primaryBranchId,
              enabled: widget.enabled,
              onBranchChecked: widget.onBranchChecked,
              onPrimaryBranchChanged: widget.onPrimaryBranchChanged,
            ),
        ],
      ],
    );
  }

  Widget _textField({
    required bool isEdit,
    required String label,
    required TextEditingController controller,
    String? currentValue,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    if (isEdit) {
      return _ModifiableTextField(
        label: label,
        currentValue: currentValue,
        controller: controller,
        hintText: hintText,
        enabled: widget.enabled,
        validator: validator,
        keyboardType: keyboardType,
      );
    }
    return AppTextField(
      label: label,
      controller: controller,
      hintText: hintText,
      enabled: widget.enabled,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
    );
  }
}

class _ModifiableTextField extends StatefulWidget {
  const _ModifiableTextField({
    required this.label,
    required this.currentValue,
    required this.controller,
    this.hintText,
    required this.enabled,
    this.validator,
    this.keyboardType,
  });

  final String label;
  final String? currentValue;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  State<_ModifiableTextField> createState() => _ModifiableTextFieldState();
}

class _ModifiableTextFieldState extends State<_ModifiableTextField> {
  var _isEditing = false;

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return AppTextField(
        label: widget.label,
        controller: widget.controller,
        hintText: widget.hintText,
        enabled: widget.enabled,
        validator: widget.validator,
        keyboardType: widget.keyboardType,
      );
    }

    final theme = Theme.of(context);
    final display = widget.currentValue?.trim();
    final hasDisplay = display != null && display.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.labelMedium),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                hasDisplay ? display : 'This value has not been set before.',
                style: hasDisplay
                    ? theme.textTheme.bodyLarge
                    : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: widget.enabled ? () => setState(() => _isEditing = true) : null,
              child: const Text('Modify'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModifiableRoleField extends StatefulWidget {
  const _ModifiableRoleField({
    required this.currentRole,
    required this.selectableRoles,
    required this.selectedRole,
    required this.enabled,
    required this.onRoleChanged,
  });

  final StaffRole? currentRole;
  final List<StaffRole> selectableRoles;
  final StaffRole? selectedRole;
  final bool enabled;
  final ValueChanged<StaffRole?> onRoleChanged;

  @override
  State<_ModifiableRoleField> createState() => _ModifiableRoleFieldState();
}

class _ModifiableRoleFieldState extends State<_ModifiableRoleField> {
  var _isEditing = false;

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      final roleItems = {for (final role in widget.selectableRoles) StaffFormFields.roleLabel(role): role};
      return AppSelect<StaffRole>(
        label: 'Role *',
        items: roleItems,
        value: widget.selectedRole,
        hintText: 'Select a role',
        enabled: widget.enabled,
        onChanged: widget.onRoleChanged,
        autovalidateMode: AutovalidateMode.disabled,
        validator: (value) => value == null ? 'Select a role' : null,
      );
    }

    final theme = Theme.of(context);
    final role = widget.currentRole;
    final display = role == null ? null : StaffFormFields.roleLabel(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Role', style: theme.textTheme.labelMedium),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                display ?? 'This value has not been set before.',
                style: display == null
                    ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                    : theme.textTheme.bodyLarge,
              ),
            ),
            TextButton(
              onPressed: widget.enabled ? () => setState(() => _isEditing = true) : null,
              child: const Text('Modify'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModifiableBranchAssignmentsField extends StatefulWidget {
  const _ModifiableBranchAssignmentsField({
    required this.currentLabel,
    required this.branchIds,
    required this.branchById,
    required this.selectedBranchIds,
    required this.primaryBranchId,
    required this.enabled,
    required this.onBranchChecked,
    required this.onPrimaryBranchChanged,
  });

  final String? currentLabel;
  final List<String> branchIds;
  final Map<String, BranchSummary> branchById;
  final Set<String> selectedBranchIds;
  final String? primaryBranchId;
  final bool enabled;
  final void Function(String branchId, bool checked) onBranchChecked;
  final ValueChanged<String?> onPrimaryBranchChanged;

  @override
  State<_ModifiableBranchAssignmentsField> createState() => _ModifiableBranchAssignmentsFieldState();
}

class _ModifiableBranchAssignmentsFieldState extends State<_ModifiableBranchAssignmentsField> {
  var _isEditing = false;

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return _BranchAssignmentsEditor(
        branchIds: widget.branchIds,
        branchById: widget.branchById,
        selectedBranchIds: widget.selectedBranchIds,
        primaryBranchId: widget.primaryBranchId,
        enabled: widget.enabled,
        onBranchChecked: widget.onBranchChecked,
        onPrimaryBranchChanged: widget.onPrimaryBranchChanged,
      );
    }

    final theme = Theme.of(context);
    final display = widget.currentLabel?.trim();
    final hasDisplay = display != null && display.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Branch assignments', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                hasDisplay ? display : 'No branches assigned.',
                style: hasDisplay
                    ? theme.textTheme.bodyLarge
                    : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: widget.enabled ? () => setState(() => _isEditing = true) : null,
              child: const Text('Modify'),
            ),
          ],
        ),
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
