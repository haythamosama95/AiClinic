import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';

/// Payment entry form for issued/partially paid invoices (V1-6 US2).
class PaymentForm extends ConsumerStatefulWidget {
  const PaymentForm({super.key, required this.invoiceId, required this.detail});

  final String invoiceId;
  final InvoiceDetail detail;

  @override
  ConsumerState<PaymentForm> createState() => PaymentFormState();
}

class PaymentFormState extends ConsumerState<PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAmountField());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PaymentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAmountField();
  }

  void _syncAmountField() {
    final panel = ref.read(paymentPanelProvider(widget.invoiceId)).value;
    final lockAmount = panel != null && _shouldLockAmount(panel.allowPartialPayments, _method);
    if (lockAmount) {
      _amountController.text = widget.detail.balance;
    }
  }

  bool _shouldLockAmount(bool allowPartialPayments, PaymentMethod method) {
    return !allowPartialPayments && method.isPatientTender;
  }

  @override
  Widget build(BuildContext context) {
    final canRecord = ref.watch(permissionServiceProvider).canRecordPayment();
    if (!canRecord) {
      return const SizedBox.shrink();
    }

    if (!_canAcceptPayment(widget.detail.status)) {
      return const SizedBox.shrink();
    }

    final panelAsync = ref.watch(paymentPanelProvider(widget.invoiceId));

    return panelAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(error.toString()),
      data: (panel) {
        final lockAmount = _shouldLockAmount(panel.allowPartialPayments, _method);
        if (lockAmount && _amountController.text != widget.detail.balance) {
          _amountController.text = widget.detail.balance;
        }

        return Card(
          key: const Key('payment_form_card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Record payment', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentMethod>(
                    key: const Key('payment_method_field'),
                    value: _method,
                    decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
                    items: PaymentMethod.values
                        .map((method) => DropdownMenuItem(value: method, child: Text(method.label)))
                        .toList(growable: false),
                    onChanged: panel.isSaving
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _method = value;
                              if (_shouldLockAmount(panel.allowPartialPayments, value)) {
                                _amountController.text = widget.detail.balance;
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Tooltip(
                    message: lockAmount
                        ? 'Partial payments are disabled for this organization. Collect the full balance.'
                        : 'Enter an amount up to the current balance.',
                    child: TextFormField(
                      key: const Key('payment_amount_field'),
                      controller: _amountController,
                      enabled: !panel.isSaving && !lockAmount,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        border: const OutlineInputBorder(),
                        suffixText: widget.detail.currency,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) {
                          return 'Amount is required.';
                        }
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid amount greater than zero.';
                        }
                        final balance = double.tryParse(widget.detail.balance) ?? 0;
                        if (parsed > balance) {
                          return 'Amount cannot exceed the current balance.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('payment_reference_field'),
                    controller: _referenceController,
                    enabled: !panel.isSaving,
                    decoration: const InputDecoration(labelText: 'Reference (optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('payment_note_field'),
                    controller: _noteController,
                    enabled: !panel.isSaving,
                    decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  if (panel.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      panel.errorMessage!,
                      key: const Key('payment_error_message'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (panel.successMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      panel.successMessage!,
                      key: const Key('payment_success_message'),
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('payment_submit_button'),
                    onPressed: panel.isSaving ? null : () => _submit(panel.allowPartialPayments),
                    child: panel.isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Record payment'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(bool allowPartialPayments) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final amount = _amountController.text.trim();
    if (!allowPartialPayments && _method.isPatientTender && amount != widget.detail.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Partial payments are not allowed for this organization; please collect the full balance.'),
        ),
      );
      return;
    }

    final success = await ref
        .read(paymentPanelProvider(widget.invoiceId).notifier)
        .recordPayment(
          method: _method,
          amount: amount,
          reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        );

    if (!mounted) {
      return;
    }

    if (success) {
      _referenceController.clear();
      _noteController.clear();
      _syncAmountField();
    }
  }

  bool _canAcceptPayment(InvoiceStatus status) {
    return status == InvoiceStatus.issued || status == InvoiceStatus.partiallyPaid;
  }
}
