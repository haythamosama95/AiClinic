import 'package:flutter/material.dart';

import 'package:ai_clinic/core/widgets/app_field_label.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/app_modifiable_form_field.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/branch_assignment_label.dart';

/// How [StaffFormFields] validates and presents staff inputs.
enum StaffFormFieldsMode {
  /// Settings create: standard form fields.
  create,

  /// Settings edit: read-only values with **Modify** before editing.
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
class StaffFormFields extends StatelessWidget {
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

  static String roleLabel(StaffRole role) => switch (role) {
    StaffRole.owner => 'Owner',
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };

  @override
  Widget build(BuildContext context) {
    final isEdit = mode == StaffFormFieldsMode.edit;
    final isCreate = mode == StaffFormFieldsMode.create;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCreate) ...[
          AppFormField(
            label: 'Username',
            infoTooltip: 'Work username used for clinic sign-in.',
            controller: usernameController,
            enabled: enabled,
            validator: (value) => validateStaffUsername(value ?? ''),
          ),
          const SizedBox(height: 16),
        ],
        _textField(
          isEdit: isEdit,
          label: 'Full name',
          currentValue: existing?.fullName,
          controller: fullNameController,
          validator: (value) {
            final serverError = fieldErrors['fullName'];
            if (serverError != null) {
              return serverError;
            }
            if (value == null || value.trim().isEmpty) {
              return 'Full name is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _textField(
          isEdit: isEdit,
          label: 'Phone (optional)',
          currentValue: existing?.phone,
          controller: phoneController,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        if (isEdit)
          _ModifiableRoleField(
            currentRole: existing?.role,
            selectableRoles: selectableRoles,
            selectedRole: selectedRole,
            enabled: enabled,
            onRoleChanged: onRoleChanged,
          )
        else
          DropdownButtonFormField<StaffRole>(
            value: selectedRole,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [for (final role in selectableRoles) DropdownMenuItem(value: role, child: Text(roleLabel(role)))],
            onChanged: enabled ? onRoleChanged : null,
            validator: (value) => value == null ? 'Select a role' : null,
          ),
        const SizedBox(height: 16),
        if (isEdit)
          _ModifiableBranchAssignmentsField(
            currentLabel: existing?.branchAssignmentLabel,
            branchIds: branchIds,
            branchById: branchById,
            selectedBranchIds: selectedBranchIds,
            primaryBranchId: primaryBranchId,
            enabled: enabled,
            onBranchChecked: onBranchChecked,
            onPrimaryBranchChanged: onPrimaryBranchChanged,
          )
        else
          _BranchAssignmentsEditor(
            branchIds: branchIds,
            branchById: branchById,
            selectedBranchIds: selectedBranchIds,
            primaryBranchId: primaryBranchId,
            enabled: enabled,
            onBranchChecked: onBranchChecked,
            onPrimaryBranchChanged: onPrimaryBranchChanged,
          ),
        if (isCreate) ...[
          const SizedBox(height: 16),
          AppFormField(
            label: 'Initial password',
            infoTooltip: 'Shown once after creation so you can share it with the staff member.',
            controller: passwordController,
            enabled: enabled,
            obscureText: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Password is required';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
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
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    if (isEdit) {
      return AppModifiableFormField(
        label: label,
        currentValue: currentValue,
        controller: controller,
        enabled: enabled,
        validator: validator,
        keyboardType: keyboardType,
      );
    }
    return AppFormField(
      label: label,
      controller: controller,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
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
  bool _isEditing = false;

  void _startEditing() {
    if (!widget.enabled) {
      return;
    }
    setState(() => _isEditing = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return DropdownButtonFormField<StaffRole>(
        value: widget.selectedRole,
        decoration: const InputDecoration(labelText: 'Role'),
        items: [
          for (final role in widget.selectableRoles)
            DropdownMenuItem(value: role, child: Text(StaffFormFields.roleLabel(role))),
        ],
        onChanged: widget.enabled ? widget.onRoleChanged : null,
        validator: (value) => value == null ? 'Select a role' : null,
      );
    }

    final theme = Theme.of(context);
    final role = widget.currentRole;
    final display = role == null ? null : StaffFormFields.roleLabel(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppFieldLabel(label: 'Role'),
        const SizedBox(height: 8),
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
            TextButton(onPressed: widget.enabled ? _startEditing : null, child: const Text('Modify')),
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
  bool _isEditing = false;

  void _startEditing() {
    if (!widget.enabled) {
      return;
    }
    setState(() => _isEditing = true);
  }

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
        const SizedBox(height: 8),
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
            TextButton(onPressed: widget.enabled ? _startEditing : null, child: const Text('Modify')),
          ],
        ),
      ],
    );
  }
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
        Text('Branch assignments', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (branchIds.isEmpty)
          Text(
            'No active branches are available. Create or reactivate a branch first.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...branchIds.map((branchId) {
            final selected = selectedBranchIds.contains(branchId);
            return CheckboxListTile(
              value: selected,
              onChanged: enabled ? (checked) => onBranchChecked(branchId, checked == true) : null,
              title: BranchAssignmentLabel(branch: branchById[branchId], fallbackLabel: 'Branch $branchId'),
              subtitle: const Text('Staff can work at this location'),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
        if (selectedBranchIds.length > 1) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: primaryBranchId,
            decoration: const InputDecoration(labelText: 'Primary branch'),
            items: [
              for (final id in selectedBranchIds)
                DropdownMenuItem(
                  value: id,
                  child: BranchAssignmentLabel(branch: branchById[id], fallbackLabel: 'Branch $id'),
                ),
            ],
            onChanged: enabled ? onPrimaryBranchChanged : null,
          ),
        ],
      ],
    );
  }
}
