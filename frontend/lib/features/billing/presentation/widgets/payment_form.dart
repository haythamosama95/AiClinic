import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Payment recording form for issued invoices (V1-6 US2).
class PaymentForm extends StatefulWidget {
  const PaymentForm({
    required this.invoice,
    required this.allowPartialPayments,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });

  final InvoiceDetail invoice;
  final bool allowPartialPayments;
  final bool enabled;
  final Future<void> Function(PaymentMethod method, String amount, String? reference, String? note) onSubmit;

  @override
  State<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentForm> {
  PaymentMethod _method = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _syncAmount();
  }

  @override
  void didUpdateWidget(PaymentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.balance != widget.invoice.balance ||
        oldWidget.allowPartialPayments != widget.allowPartialPayments ||
        oldWidget.invoice.id != widget.invoice.id) {
      _syncAmount();
    }
  }

  void _syncAmount() {
    final balance = widget.invoice.balance.wireValue;
    final lockAmount = !widget.allowPartialPayments && _method.isPatientTender;
    _amountController.text = balance;
    if (lockAmount) {
      _amountController.selection = TextSelection.collapsed(offset: balance.length);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _amountLocked => !widget.allowPartialPayments && _method.isPatientTender;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(
        _method,
        _amountController.text.trim(),
        _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      _referenceController.clear();
      _noteController.clear();
      _syncAmount();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balanceLabel = BillingFormatting.formatMoney(widget.invoice.balance, currency: widget.invoice.currency);

    return AppCard(
      title: const Text('Record payment'),
      description: Text('Balance due: $balanceLabel'),
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.6,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppLabel(
                label: 'Payment method',
                child: AppSelectTileGroup<PaymentMethod>(
                  mode: AppSelectGroupMode.radio,
                  options: [
                    for (final method in PaymentMethod.values) AppSelectOption(value: method, label: method.label),
                  ],
                  values: {_method},
                  onChanged: (values) {
                    if (values.isNotEmpty) {
                      setState(() {
                        _method = values.first;
                        _syncAmount();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: SpacingTokens.md),
              AppTextField(
                controller: _amountController,
                label: 'Amount',
                enabled: !_amountLocked,
                hintText: balanceLabel,
              ),
              if (_amountLocked) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  'Partial payments are disabled. Collect the full balance.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ],
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(controller: _referenceController, label: 'Reference (optional)'),
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(controller: _noteController, label: 'Note (optional)'),
              const SizedBox(height: SpacingTokens.md),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(label: 'Record payment', isLoading: _isSubmitting, expand: false, onPressed: _submit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
