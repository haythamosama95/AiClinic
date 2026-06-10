import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';

class SetupBranchStep extends StatelessWidget {
  const SetupBranchStep({
    required this.formKey,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    required this.isBusy,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SetupStepLayout(
        body: SetupFormGrid(
          children: [
            AppTextField(
              label: 'Branch name *',
              controller: nameController,
              hintText: 'Enter branch name',
              enabled: !isBusy,
              validator: _requiredValidator('Branch name'),
            ),
            AppTextField(
              label: 'Branch code *',
              controller: codeController,
              hintText: 'e.g. MAIN',
              enabled: !isBusy,
              validator: _requiredValidator('Branch code'),
            ),
            AppTextField(
              label: 'Address *',
              controller: addressController,
              hintText: 'Street address',
              enabled: !isBusy,
              validator: _requiredValidator('Address'),
            ),
            AppTextField(
              label: 'Phone *',
              controller: phoneController,
              hintText: 'Numbers only',
              enabled: !isBusy,
              keyboardType: TextInputType.phone,
              validator: BranchFieldValidation.validatePhone,
            ),
            AppTextField(
              label: 'Maps URL *',
              controller: mapsUrlController,
              hintText: 'maps.google.com/... or www.example.com',
              enabled: !isBusy,
              keyboardType: TextInputType.url,
              validator: BranchFieldValidation.validateMapsUrl,
            ),
          ],
        ),
      ),
    );
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
