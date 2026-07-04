import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/branch_working_hours_editor.dart';

/// Organization step inputs for the bootstrap wizard.
class BootstrapOrganizationStepFields extends StatelessWidget {
  const BootstrapOrganizationStepFields({
    required this.nameController,
    required this.logoUrlController,
    required this.currency,
    required this.timezone,
    required this.onCurrencyChanged,
    required this.onTimezoneChanged,
    required this.fieldErrors,
    required this.onFieldBlur,
    required this.disabled,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController logoUrlController;
  final String? currency;
  final String? timezone;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<String?> onTimezoneChanged;
  final Map<String, String?> fieldErrors;
  final void Function(String field) onFieldBlur;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final currencyOptions = [
      for (final code in BootstrapCurrencyOptions.codes)
        AppSelectOption<String>(value: code, label: code),
    ];
    final timezoneOptions = [
      for (final zone in BootstrapTimezoneOptions.zones)
        AppSelectOption<String>(value: zone, label: zone),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: 'Organization name',
          requiredMark: true,
          error: fieldErrors['name'],
          child: AppTextField(
            controller: nameController,
            hintText: 'Enter your clinic name',
            disabled: disabled,
            invalid: fieldErrors['name'] != null,
            onChanged: (_) => onFieldBlur('name'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Logo URL',
          hint: 'HTTPS link to your clinic logo. Leave blank if you add a logo later.',
          error: fieldErrors['logoUrl'],
          child: AppTextField(
            controller: logoUrlController,
            hintText: 'https://example.com/logo.png',
            disabled: disabled,
            keyboardType: TextInputType.url,
            invalid: fieldErrors['logoUrl'] != null,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Currency code',
          requiredMark: true,
          hint: 'ISO 4217 code for billing and receipts (e.g. EGP, USD).',
          error: fieldErrors['currency'],
          child: AppSelect<String>(
            options: currencyOptions,
            value: currency,
            placeholder: 'Type to search (e.g. EGP)',
            disabled: disabled,
            invalid: fieldErrors['currency'] != null,
            onChanged: disabled ? null : onCurrencyChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Timezone',
          requiredMark: true,
          hint: 'IANA timezone for appointments and daily reports (e.g. Africa/Cairo).',
          error: fieldErrors['timezone'],
          child: AppSelect<String>(
            options: timezoneOptions,
            value: timezone,
            placeholder: 'Type to search (e.g. Africa/Cairo)',
            disabled: disabled,
            invalid: fieldErrors['timezone'] != null,
            onChanged: disabled ? null : onTimezoneChanged,
          ),
        ),
      ],
    );
  }
}

/// Branch step inputs for the bootstrap wizard.
class BootstrapBranchStepFields extends StatelessWidget {
  const BootstrapBranchStepFields({
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    required this.workingSchedule,
    required this.onWorkingScheduleChanged,
    required this.fieldErrors,
    required this.onFieldBlur,
    required this.disabled,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final BranchWorkingSchedule workingSchedule;
  final ValueChanged<BranchWorkingSchedule> onWorkingScheduleChanged;
  final Map<String, String?> fieldErrors;
  final void Function(String field) onFieldBlur;
  final bool disabled;

  Future<void> _openWorkingHours(BuildContext context) async {
    final updated = await showBranchWorkingHoursEditor(context, initialSchedule: workingSchedule);
    if (updated != null) {
      onWorkingScheduleChanged(updated);
      onFieldBlur('workingHours');
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = workingSchedule.hasConfiguredWorkingHours;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: 'Branch name',
          requiredMark: true,
          error: fieldErrors['branchName'],
          child: AppTextField(
            controller: nameController,
            hintText: 'Enter branch name',
            disabled: disabled,
            invalid: fieldErrors['branchName'] != null,
            onChanged: (_) => onFieldBlur('branchName'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Branch code',
          requiredMark: true,
          error: fieldErrors['branchCode'],
          child: AppTextField(
            controller: codeController,
            hintText: 'e.g. MAIN',
            disabled: disabled,
            invalid: fieldErrors['branchCode'] != null,
            onChanged: (_) => onFieldBlur('branchCode'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Address',
          requiredMark: true,
          error: fieldErrors['address'],
          child: AppTextField(
            controller: addressController,
            hintText: 'Street address',
            disabled: disabled,
            invalid: fieldErrors['address'] != null,
            onChanged: (_) => onFieldBlur('address'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Phone',
          requiredMark: true,
          error: fieldErrors['phone'],
          child: AppTextField(
            controller: phoneController,
            hintText: 'Numbers only',
            disabled: disabled,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            invalid: fieldErrors['phone'] != null,
            onChanged: (_) => onFieldBlur('phone'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Maps URL',
          requiredMark: true,
          error: fieldErrors['mapsUrl'],
          child: AppTextField(
            controller: mapsUrlController,
            hintText: 'maps.google.com/... or www.example.com',
            disabled: disabled,
            keyboardType: TextInputType.url,
            invalid: fieldErrors['mapsUrl'] != null,
            onChanged: (_) => onFieldBlur('mapsUrl'),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Working hours',
          requiredMark: true,
          error: fieldErrors['workingHours'],
          child: AppButton(
            label: configured ? 'Working hours configured' : 'Configure working hours',
            variant: AppButtonVariant.secondary,
            leadingIcon: LucideIcons.clock,
            trailingIcon: configured ? LucideIcons.check : null,
            disabled: disabled,
            onPressed: disabled ? null : () => _openWorkingHours(context),
          ),
        ),
      ],
    );
  }

  /// Validates branch text fields and working hours; returns field errors.
  static Map<String, String?> validate({
    required String branchName,
    required String branchCode,
    required String address,
    required String phone,
    required String mapsUrl,
    required BranchWorkingSchedule workingSchedule,
  }) {
    return {
      'branchName': branchName.trim().isEmpty ? 'Enter a name for your first branch.' : null,
      'branchCode': branchCode.trim().isEmpty ? 'Enter a branch code.' : null,
      'address': address.trim().isEmpty ? 'Enter the branch address.' : null,
      'phone': BranchFieldValidation.validatePhone(phone),
      'mapsUrl': BranchFieldValidation.validateMapsUrl(mapsUrl),
      'workingHours': workingSchedule.hasConfiguredWorkingHours
          ? null
          : 'Configure at least one working day with hours.',
    };
  }
}
