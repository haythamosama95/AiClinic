import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/service_form_values.dart';

/// Service catalog form fields (web `ServiceFormFields`).
class ServiceFormFields extends StatelessWidget {
  const ServiceFormFields({
    required this.idPrefix,
    required this.values,
    required this.onChange,
    required this.currency,
    this.disabled = false,
    this.errors = const {},
    super.key,
  });

  final String idPrefix;
  final ServiceFormValues values;
  final void Function(ServiceFormValues values) onChange;
  final String currency;
  final bool disabled;
  final ServiceFormErrors errors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: '$idPrefix-name',
          label: 'Service name',
          requiredMark: true,
          error: errors['name'],
          child: AppTextInput(
            id: '$idPrefix-name',
            initialValue: values.name,
            placeholder: 'e.g. Dental cleaning',
            disabled: disabled,
            readOnly: disabled,
            invalid: errors.containsKey('name'),
            onChanged: (name) => onChange(values.copyWith(name: name)),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: '$idPrefix-price',
          label: 'Default price',
          requiredMark: true,
          error: errors['price'],
          child: AppMoneyField(
            id: '$idPrefix-price',
            currency: currency,
            initialValue: values.price,
            disabled: disabled,
            readOnly: disabled,
            invalid: errors.containsKey('price'),
            onValueChange: (price) => onChange(values.copyWith(price: price, clearPrice: price == null)),
          ),
        ),
      ],
    );
  }
}
