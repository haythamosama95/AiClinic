import 'package:flutter/material.dart';

import 'package:ai_clinic/features/setup/presentation/widgets/organization_form_fields.dart';
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
        body: OrganizationFormFields(
          mode: OrganizationFormFieldsMode.create,
          nameController: nameController,
          logoUrlController: logoUrlController,
          currency: currency,
          timezone: timezone,
          onCurrencyChanged: onCurrencyChanged,
          onTimezoneChanged: onTimezoneChanged,
          enabled: !isBusy,
        ),
      ),
    );
  }
}
