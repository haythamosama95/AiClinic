import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_form_read_only_field.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_searchable_field.dart';

/// How [OrganizationFormFields] validates and presents organization inputs.
enum OrganizationFormFieldsMode {
  /// Bootstrap setup: standard editable form fields.
  create,

  /// Settings: read-only values until [isEditing] is true.
  edit,
}

/// Existing organization values for [OrganizationFormFieldsMode.edit].
@immutable
class OrganizationFormExistingData {
  const OrganizationFormExistingData({this.name, this.logoUrl, this.currencyCode, this.timezone});

  final String? name;
  final String? logoUrl;
  final String? currencyCode;
  final String? timezone;
}

/// Shared organization name, logo, currency, and timezone inputs.
class OrganizationFormFields extends StatelessWidget {
  const OrganizationFormFields({
    required this.mode,
    required this.nameController,
    required this.logoUrlController,
    required this.currency,
    required this.timezone,
    required this.onCurrencyChanged,
    required this.onTimezoneChanged,
    required this.enabled,
    this.isEditing = false,
    this.existing,
    super.key,
  });

  final OrganizationFormFieldsMode mode;
  final TextEditingController nameController;
  final TextEditingController logoUrlController;
  final String? currency;
  final String? timezone;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<String?> onTimezoneChanged;
  final bool enabled;
  final bool isEditing;
  final OrganizationFormExistingData? existing;

  bool get _showEditableFields => mode == OrganizationFormFieldsMode.create || isEditing;

  int get _columns => mode == OrganizationFormFieldsMode.edit ? 4 : 2;

  @override
  Widget build(BuildContext context) {
    if (_showEditableFields) {
      return SetupFormGrid(
        columns: _columns,
        children: [
          AppTextField(
            label: 'Organization name *',
            controller: nameController,
            hintText: 'Enter your clinic name',
            enabled: enabled,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Organization name is required';
              }
              return null;
            },
          ),
          AppTextField(
            label: 'Logo URL',
            controller: logoUrlController,
            hintText: 'https://example.com/logo.png',
            enabled: enabled,
            keyboardType: TextInputType.url,
          ),
          SetupSearchableField(
            label: 'Currency code *',
            options: BootstrapCurrencyOptions.codes,
            value: currency,
            hintText: 'Type to search (e.g. EGP)',
            enabled: enabled,
            onChanged: onCurrencyChanged,
            validator: (value) {
              if (!BootstrapCurrencyOptions.isValid(value)) {
                return 'Select a currency code from the list';
              }
              return null;
            },
          ),
          SetupSearchableField(
            label: 'Timezone *',
            options: BootstrapTimezoneOptions.zones,
            value: timezone,
            hintText: 'Type to search (e.g. Africa/Cairo)',
            enabled: enabled,
            onChanged: onTimezoneChanged,
            validator: (value) {
              if (!BootstrapTimezoneOptions.isValid(value)) {
                return 'Select a timezone from the list';
              }
              return null;
            },
          ),
        ],
      );
    }

    final data = existing;
    return SetupFormGrid(
      columns: _columns,
      children: [
        ClinicFormReadOnlyField(label: 'Organization name', value: data?.name),
        ClinicFormReadOnlyField(label: 'Logo URL', value: data?.logoUrl),
        ClinicFormReadOnlyField(label: 'Currency code', value: data?.currencyCode),
        ClinicFormReadOnlyField(label: 'Timezone', value: data?.timezone),
      ],
    );
  }
}
