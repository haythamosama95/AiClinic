import 'package:flutter/material.dart';

import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/app_modifiable_form_field.dart';

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
  const BranchFormExistingData({this.name, this.code, this.address, this.phone, this.mapsUrl});

  final String? name;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;
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
      ],
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
}
