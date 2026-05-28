import 'package:flutter/material.dart';

import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/app_field_label.dart';
import 'package:ai_clinic/core/widgets/app_modifiable_form_field.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// How [BranchFormFields] validates and presents branch inputs.
enum BranchFormFieldsMode {
  /// Clinic bootstrap: all fields required.
  bootstrap,

  /// Settings create: branch name required; other fields optional.
  create,

  /// Settings edit: read-only values with **Modify** before editing.
  edit,
}

/// Existing branch values for [BranchFormFieldsMode.edit].
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
///
/// Used by clinic bootstrap and settings branch create/edit so field labels,
/// hints, tooltips, and validation stay in one place.
class BranchFormFields extends StatelessWidget {
  const BranchFormFields({
    super.key,
    required this.mode,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    this.dayEnabled = const {},
    this.openTimeControllers = const {},
    this.closeTimeControllers = const {},
    this.onDayEnabledChanged,
    this.existing,
    this.enabled = true,
    this.fieldErrors = const {},
  });

  final BranchFormFieldsMode mode;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final Map<BranchWeekday, bool> dayEnabled;
  final Map<BranchWeekday, TextEditingController> openTimeControllers;
  final Map<BranchWeekday, TextEditingController> closeTimeControllers;
  final void Function(BranchWeekday day, bool enabled)? onDayEnabledChanged;
  final BranchFormExistingData? existing;
  final bool enabled;
  final Map<String, String> fieldErrors;

  static const _nameTooltip = 'Name staff recognize (e.g. Main Clinic, Downtown Branch).';
  static const _codeTooltip = 'Short internal code for reports and branch switching (e.g. MAIN, DT01).';
  static const _addressTooltip = 'Street address shown to staff and on patient communications.';
  static const _phoneTooltip = 'Branch reception or main line including country code.';
  static const _mapsTooltip = 'Google Maps or similar link patients can open for directions.';

  @override
  Widget build(BuildContext context) {
    final isEdit = mode == BranchFormFieldsMode.edit;
    final isBootstrap = mode == BranchFormFieldsMode.bootstrap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          isEdit: isEdit,
          label: 'Branch name',
          infoTooltip: _nameTooltip,
          currentValue: existing?.name,
          controller: nameController,
          validator: (value) =>
              fieldErrors['name'] ?? (value == null || value.trim().isEmpty ? 'Branch name is required.' : null),
        ),
        const SizedBox(height: 16),
        _field(
          isEdit: isEdit,
          label: 'Branch code',
          infoTooltip: _codeTooltip,
          currentValue: existing?.code,
          controller: codeController,
          hint: isBootstrap ? null : 'Optional unique code',
          validator: (value) {
            final serverError = fieldErrors['code'];
            if (serverError != null) {
              return serverError;
            }
            if (isBootstrap && (value == null || value.trim().isEmpty)) {
              return 'Branch code is required.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _field(
          isEdit: isEdit,
          label: 'Address',
          infoTooltip: _addressTooltip,
          currentValue: existing?.address,
          controller: addressController,
          validator: isBootstrap ? _requiredValidator('Address') : null,
        ),
        const SizedBox(height: 16),
        _field(
          isEdit: isEdit,
          label: 'Phone',
          infoTooltip: _phoneTooltip,
          currentValue: existing?.phone,
          controller: phoneController,
          keyboardType: TextInputType.phone,
          validator: isBootstrap ? _requiredValidator('Phone') : null,
        ),
        const SizedBox(height: 16),
        _field(
          isEdit: isEdit,
          label: 'Maps URL',
          infoTooltip: _mapsTooltip,
          currentValue: existing?.mapsUrl,
          controller: mapsUrlController,
          hint: isBootstrap ? null : 'https://…',
          keyboardType: TextInputType.url,
          validator: (value) {
            if (isBootstrap) {
              return _mapsUrlBootstrapValidator(value);
            }
            return null;
          },
        ),
        if (openTimeControllers.isNotEmpty && closeTimeControllers.isNotEmpty && onDayEnabledChanged != null) ...[
          const SizedBox(height: 24),
          Text('Working days and hours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Select branch working days, then pick opening and closing times.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final day in BranchWeekday.values) ...[_workingDayRow(context, day), const SizedBox(height: 8)],
        ],
      ],
    );
  }

  Widget _workingDayRow(BuildContext context, BranchWeekday day) {
    final isEnabled = dayEnabled[day] ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(day.label)),
              Checkbox(
                value: isEnabled,
                onChanged: enabled ? (value) => onDayEnabledChanged?.call(day, value ?? false) : null,
              ),
              const SizedBox(width: 6),
              const Text('Working day'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Open',
                  controller: openTimeControllers[day]!,
                  enabled: enabled && isEnabled,
                  hint: 'Select time',
                  validator: (_) => _timeValidatorFor(day, isEnabled, isOpen: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimePickerField(
                  label: 'Close',
                  controller: closeTimeControllers[day]!,
                  enabled: enabled && isEnabled,
                  hint: 'Select time',
                  validator: (_) => _timeValidatorFor(day, isEnabled, isOpen: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required bool isEdit,
    required String label,
    required TextEditingController controller,
    String? currentValue,
    String? infoTooltip,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    if (isEdit) {
      return AppModifiableFormField(
        label: label,
        infoTooltip: infoTooltip,
        currentValue: currentValue,
        controller: controller,
        enabled: enabled,
        hint: hint,
        validator: validator,
        keyboardType: keyboardType,
      );
    }
    return AppFormField(
      label: label,
      infoTooltip: infoTooltip,
      controller: controller,
      enabled: enabled,
      hint: hint,
      validator: validator,
      keyboardType: keyboardType,
    );
  }

  static String? Function(String?) _requiredValidator(String fieldName) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return '$fieldName is required.';
      }
      return null;
    };
  }

  static String? _mapsUrlBootstrapValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Maps URL is required.';
    }
    final trimmed = value.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'Enter a valid URL starting with http:// or https://';
    }
    return null;
  }

  String? _timeValidatorFor(BranchWeekday day, bool isEnabled, {required bool isOpen}) {
    if (!isEnabled) {
      return null;
    }
    final openText = openTimeControllers[day]!.text.trim();
    final closeText = closeTimeControllers[day]!.text.trim();
    if (openText.isEmpty || closeText.isEmpty) {
      return 'Working hours are required for selected days.';
    }
    final openMinutes = _parseHm(openText);
    final closeMinutes = _parseHm(closeText);
    if (openMinutes == null || closeMinutes == null) {
      return 'Use HH:mm format (e.g. 09:00).';
    }
    if (openMinutes >= closeMinutes) {
      return isOpen ? 'Open time must be before close time.' : null;
    }
    return null;
  }

  static int? _parseHm(String input) {
    final normalized = input.trim();
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
}

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.hint,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          enabled: enabled,
          validator: validator,
          decoration: InputDecoration(hintText: hint, suffixIcon: const Icon(Icons.access_time)),
          onTap: !enabled
              ? null
              : () async {
                  final initialTime = _parseTime(controller.text) ?? const TimeOfDay(hour: 9, minute: 0);
                  final picked = await showTimePicker(context: context, initialTime: initialTime);
                  if (picked == null) {
                    return;
                  }
                  controller.text = _formatHm(picked);
                },
        ),
      ],
    );
  }

  static TimeOfDay? _parseTime(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return TimeOfDay(hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
  }

  static String _formatHm(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
