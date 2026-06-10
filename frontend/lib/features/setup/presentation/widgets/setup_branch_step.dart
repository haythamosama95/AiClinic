import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_form_grid.dart';

class SetupBranchStep extends StatelessWidget {
  const SetupBranchStep({
    required this.formKey,
    required this.nameController,
    required this.codeController,
    required this.addressController,
    required this.phoneController,
    required this.mapsUrlController,
    required this.isBusy,
    required this.onSubmit,
    this.onBack,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController mapsUrlController;
  final bool isBusy;
  final Future<void> Function() onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetupFormGrid(
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
                hintText: 'Branch phone number',
                enabled: !isBusy,
                keyboardType: TextInputType.phone,
                validator: _requiredValidator('Phone'),
              ),
              AppTextField(
                label: 'Maps URL *',
                controller: mapsUrlController,
                hintText: 'https://maps.google.com/...',
                enabled: !isBusy,
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Maps URL is required';
                  }
                  final trimmed = value.trim();
                  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
                    return 'Enter a valid URL starting with https://';
                  }
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onBack != null) ...[
                AppButton(label: 'Back', variant: AppButtonVariant.outline, onPressed: isBusy ? null : onBack),
                const SizedBox(width: SpacingTokens.md),
              ],
              AppButton(label: 'Next', isLoading: isBusy, onPressed: isBusy ? null : onSubmit),
            ],
          ),
        ],
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
