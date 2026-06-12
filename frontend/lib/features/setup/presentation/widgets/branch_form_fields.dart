import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_form_read_only_field.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

/// How [BranchFormFields] validates and presents branch inputs.
enum BranchFormFieldsMode {
  /// Bootstrap setup: standard editable form fields.
  create,

  /// Settings: read-only values until [isEditing] is true.
  edit,

  /// Settings: read-only display with no edit affordance.
  readOnly,
}

/// Existing branch values for [BranchFormFieldsMode.edit] and [BranchFormFieldsMode.readOnly].
@immutable
class BranchFormExistingData {
  const BranchFormExistingData({this.name, this.code, this.address, this.phone, this.mapsUrl, this.workingSchedule});

  final String? name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
  final BranchWorkingSchedule? workingSchedule;
}

/// Shared branch name, code, address, phone, and maps URL inputs.
class BranchFormFields extends StatelessWidget {
  const BranchFormFields({
    required this.mode,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    required this.enabled,
    this.isEditing = false,
    this.existing,
    this.onWorkingHours,
    this.workingHoursConfigured = false,
    super.key,
  });

  final BranchFormFieldsMode mode;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final bool enabled;
  final bool isEditing;
  final BranchFormExistingData? existing;

  /// Setup create mode only: opens the working-hours sheet beside Maps URL.
  final VoidCallback? onWorkingHours;

  /// Setup create mode only: shows a check mark when working hours are configured.
  final bool workingHoursConfigured;

  bool get _showEditableFields => mode == BranchFormFieldsMode.create || isEditing;

  bool get _useSettingsLayout => mode != BranchFormFieldsMode.create;

  @override
  Widget build(BuildContext context) {
    if (_useSettingsLayout) {
      return SetupFormGrid(
        columns: 2,
        compactBreakpoint: SetupFormGrid.settingsCardBreakpoint,
        children: _showEditableFields ? _editableSettingsFields() : _readOnlySettingsFields(),
      );
    }

    return SetupFormGrid(children: _editableBootstrapFields());
  }

  List<Widget> _editableBootstrapFields() {
    return [
      AppTextField(
        label: 'Branch name *',
        controller: nameController,
        hintText: 'Enter branch name',
        enabled: enabled,
        validator: _requiredValidator('Branch name'),
      ),
      AppTextField(
        label: 'Branch code *',
        controller: codeController,
        hintText: 'e.g. MAIN',
        enabled: enabled,
        validator: _requiredValidator('Branch code'),
      ),
      AppTextField(
        label: 'Address *',
        controller: addressController,
        hintText: 'Street address',
        enabled: enabled,
        validator: _requiredValidator('Address'),
      ),
      AppTextField(
        label: 'Phone *',
        controller: phoneController,
        hintText: 'Numbers only',
        enabled: enabled,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: BranchFieldValidation.validatePhone,
      ),
      AppTextField(
        label: 'Maps URL *',
        controller: mapsUrlController,
        hintText: 'maps.google.com/... or www.example.com',
        enabled: enabled,
        keyboardType: TextInputType.url,
        validator: BranchFieldValidation.validateMapsUrl,
      ),
      if (onWorkingHours != null)
        FormField<void>(
          validator: (_) => workingHoursConfigured ? null : 'Working hours are required',
          autovalidateMode: AutovalidateMode.onUserInteraction,
          builder: (state) {
            final theme = Theme.of(state.context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BranchWorkingHoursField(
                  enabled: enabled,
                  isConfigured: workingHoursConfigured,
                  onPressed: onWorkingHours!,
                ),
                if (state.hasError && state.errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: SpacingTokens.xs),
                    child: Text(
                      state.errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            );
          },
        ),
    ];
  }

  List<Widget> _editableSettingsFields() {
    return [
      AppTextField(
        label: 'Branch name *',
        controller: nameController,
        hintText: 'Enter branch name',
        enabled: enabled,
        validator: _requiredValidator('Branch name'),
      ),
      AppTextField(
        label: 'Branch code *',
        controller: codeController,
        hintText: 'e.g. MAIN',
        enabled: enabled,
        validator: _requiredValidator('Branch code'),
      ),
      AppTextField(
        label: 'Address *',
        controller: addressController,
        hintText: 'Street address',
        enabled: enabled,
        validator: _requiredValidator('Address'),
      ),
      AppTextField(
        label: 'Phone *',
        controller: phoneController,
        hintText: 'Numbers only',
        enabled: enabled,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: BranchFieldValidation.validatePhone,
      ),
      AppTextField(
        label: 'Maps URL *',
        controller: mapsUrlController,
        hintText: 'maps.google.com/... or www.example.com',
        enabled: enabled,
        keyboardType: TextInputType.url,
        validator: BranchFieldValidation.validateMapsUrl,
      ),
    ];
  }

  List<Widget> _readOnlySettingsFields() {
    return [
      ClinicFormReadOnlyField(label: 'Branch name', value: existing?.name),
      ClinicFormReadOnlyField(label: 'Branch code', value: existing?.code),
      ClinicFormReadOnlyField(label: 'Address', value: existing?.address),
      ClinicFormReadOnlyField(label: 'Phone', value: existing?.phone),
      ClinicFormReadOnlyField(label: 'Maps URL', value: existing?.mapsUrl),
    ];
  }

  static String? Function(String?) _requiredValidator(String fieldName) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return '$fieldName is required';
      }
      return null;
    };
  }
}

class _BranchWorkingHoursField extends StatelessWidget {
  const _BranchWorkingHoursField({required this.enabled, required this.isConfigured, required this.onPressed});

  final bool enabled;
  final bool isConfigured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Working hours *', style: theme.textTheme.labelMedium),
        const SizedBox(height: SpacingTokens.sm),
        FButton(
          variant: FButtonVariant.outline,
          size: AppFieldSize.md.buttonSize,
          mainAxisSize: MainAxisSize.max,
          onPress: enabled ? onPressed : null,
          prefix: Icon(Icons.schedule_outlined, size: 18, color: colors.foreground),
          suffix: isConfigured ? Icon(Icons.check, size: 18, color: colors.primary) : null,
          child: const Text('Working hours'),
        ),
      ],
    );
  }
}
