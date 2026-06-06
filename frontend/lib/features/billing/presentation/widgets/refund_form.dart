import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';

/// Refund entry form for paid/partially paid invoices (V1-6 US2).
class RefundForm extends ConsumerStatefulWidget {
  const RefundForm({super.key, required this.invoiceId, required this.detail});

  final String invoiceId;
  final InvoiceDetail detail;

  @override
  ConsumerState<RefundForm> createState() => RefundFormState();
}

class RefundFormState extends ConsumerState<RefundForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double get _netRefundablePayments {
    return widget.detail.payments.fold<double>(0, (total, payment) {
      return total + payment.amount.asDouble;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canRefund = ref.watch(permissionServiceProvider).canRefundPayment();
    if (!canRefund || !_canRefund(widget.detail.status, _netRefundablePayments)) {
      return const SizedBox.shrink();
    }

    final panelAsync = ref.watch(paymentPanelProvider(widget.invoiceId));
    final maxRefund = _netRefundablePayments;

    return panelAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (panel) {
        return Card(
          key: const Key('refund_form_card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Record refund', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentMethod>(
                    key: const Key('refund_method_field'),
                    value: _method,
                    decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
                    items: PaymentMethod.values
                        .map((method) => DropdownMenuItem(value: method, child: Text(method.label)))
                        .toList(growable: false),
                    onChanged: panel.isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _method = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('refund_amount_field'),
                    controller: _amountController,
                    enabled: !panel.isSaving,
                    decoration: InputDecoration(
                      labelText: 'Refund amount',
                      border: const OutlineInputBorder(),
                      suffixText: widget.detail.currency,
                      helperText: 'Maximum refundable: ${maxRefund.toStringAsFixed(2)}',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return 'Refund amount is required.';
                      }
                      final parsed = double.tryParse(trimmed);
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a valid amount greater than zero.';
                      }
                      if (parsed > maxRefund) {
                        return 'Refund cannot exceed net payments on this invoice.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('refund_reason_field'),
                    controller: _reasonController,
                    enabled: !panel.isSaving,
                    decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'A refund reason is required.';
                      }
                      return null;
                    },
                  ),
                  if (panel.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(panel.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('refund_submit_button'),
                    onPressed: panel.isSaving ? null : _submit,
                    child: panel.isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Record refund'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final success = await ref
        .read(paymentPanelProvider(widget.invoiceId).notifier)
        .recordRefund(method: _method, amount: _amountController.text.trim(), note: _reasonController.text.trim());

    if (!mounted) {
      return;
    }

    if (success) {
      _amountController.clear();
      _reasonController.clear();
    }
  }

  bool _canRefund(InvoiceStatus status, double netRefundablePayments) {
    if (netRefundablePayments <= 0 || status == InvoiceStatus.voided) {
      return false;
    }
    return true;
  }
}
