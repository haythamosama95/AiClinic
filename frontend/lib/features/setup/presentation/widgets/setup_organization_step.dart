import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_searchable_field.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';

class SetupOrganizationStep extends StatelessWidget {
  const SetupOrganizationStep({
    required this.formKey,
    required this.nameController,
    required this.logoUrlController,
    required this.currency,
    required this.timezone,
    required this.onCurrencyChanged,
    required this.onTimezoneChanged,
    required this.isBusy,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController logoUrlController;
  final String? currency;
  final String? timezone;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<String?> onTimezoneChanged;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SetupStepLayout(
        body: SetupFormGrid(
          children: [
            AppTextField(
              label: 'Organization name *',
              controller: nameController,
              hintText: 'Enter your clinic name',
              enabled: !isBusy,
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
              enabled: !isBusy,
              keyboardType: TextInputType.url,
            ),
            SetupSearchableField(
              label: 'Currency code *',
              options: BootstrapCurrencyOptions.codes,
              value: currency,
              hintText: 'Type to search (e.g. EGP)',
              enabled: !isBusy,
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
              enabled: !isBusy,
              onChanged: onTimezoneChanged,
              validator: (value) {
                if (!BootstrapTimezoneOptions.isValid(value)) {
                  return 'Select a timezone from the list';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
