import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Refund form gated by [payments.refund] permission (V1-6 US2).
class RefundForm extends StatefulWidget {
  const RefundForm({required this.enabled, required this.onSubmit, super.key});

  final bool enabled;
  final Future<void> Function(PaymentMethod method, String amount, String note) onSubmit;

  @override
  State<RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends State<RefundForm> {
  PaymentMethod _method = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  var _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(_method, _amountController.text.trim(), note);
      _amountController.clear();
      _noteController.clear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: const Text('Record refund'),
      description: const Text('Refunds are recorded as negative payments and require a reason.'),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.6,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSelectTileGroup<PaymentMethod>(
                mode: AppSelectGroupMode.radio,
                options: [
                  for (final method in PaymentMethod.values) AppSelectOption(value: method, label: method.label),
                ],
                values: {_method},
                onChanged: (values) {
                  if (values.isNotEmpty) {
                    setState(() => _method = values.first);
                  }
                },
              ),
              const SizedBox(height: SpacingTokens.md),
              AppTextField(controller: _amountController, label: 'Refund amount'),
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(controller: _noteController, label: 'Reason (required)'),
              const SizedBox(height: SpacingTokens.md),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'Record refund',
                  variant: AppButtonVariant.destructive,
                  isLoading: _isSubmitting,
                  expand: false,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
