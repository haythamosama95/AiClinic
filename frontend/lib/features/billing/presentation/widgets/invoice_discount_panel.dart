import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';

typedef InvoiceDiscountSubmit = Future<bool> Function({required DiscountKind kind, required String value});

typedef InvoiceDiscountClear = Future<bool> Function();

/// Invoice-level discount input for draft invoices (V1-6 US3).
class InvoiceDiscountPanel extends StatefulWidget {
  const InvoiceDiscountPanel({
    super.key,
    required this.detail,
    required this.enabled,
    required this.busy,
    required this.onApply,
    required this.onClear,
  });

  final InvoiceDetail detail;
  final bool enabled;
  final bool busy;
  final InvoiceDiscountSubmit onApply;
  final InvoiceDiscountClear onClear;

  @override
  State<InvoiceDiscountPanel> createState() => _InvoiceDiscountPanelState();
}

class _InvoiceDiscountPanelState extends State<InvoiceDiscountPanel> {
  DiscountKind _kind = DiscountKind.percentage;
  final _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncFromDetail();
  }

  @override
  void didUpdateWidget(covariant InvoiceDiscountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.updatedAt != widget.detail.updatedAt ||
        oldWidget.detail.discountKind != widget.detail.discountKind ||
        oldWidget.detail.discountValue != widget.detail.discountValue) {
      _syncFromDetail();
    }
  }

  void _syncFromDetail() {
    _kind = widget.detail.discountKind ?? DiscountKind.percentage;
    _valueController.text = widget.detail.discountValue ?? '';
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  String? _validateValue(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Discount value is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return 'Enter a valid non-negative amount.';
    }
    final subtotal = double.tryParse(widget.detail.subtotal) ?? 0;
    if (_kind == DiscountKind.percentage && parsed > 100) {
      return 'Percentage cannot exceed 100.';
    }
    if (_kind == DiscountKind.fixed && parsed > subtotal) {
      return 'Fixed discount cannot exceed the invoice subtotal.';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validateValue(_valueController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await widget.onApply(kind: _kind, value: _valueController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscount = widget.detail.discountKind != null || (double.tryParse(widget.detail.discountAmount) ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Invoice discount', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<DiscountKind>(
                key: const Key('invoice_discount_kind'),
                value: _kind,
                decoration: const InputDecoration(labelText: 'Kind', border: OutlineInputBorder()),
                items: DiscountKind.values
                    .map((kind) => DropdownMenuItem(value: kind, child: Text(kind.label)))
                    .toList(growable: false),
                onChanged: widget.enabled && !widget.busy
                    ? (value) {
                        if (value != null) {
                          setState(() => _kind = value);
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('invoice_discount_value'),
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: _kind == DiscountKind.percentage ? 'Percent' : 'Amount',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                enabled: widget.enabled && !widget.busy,
              ),
            ),
          ],
        ),
        if (hasDiscount)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Applied invoice discount: ${widget.detail.discountAmount} ${widget.detail.currency}'),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              key: const Key('invoice_discount_apply'),
              onPressed: widget.enabled && !widget.busy ? _submit : null,
              child: const Text('Apply invoice discount'),
            ),
            if (hasDiscount) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const Key('invoice_discount_clear'),
                onPressed: widget.enabled && !widget.busy ? widget.onClear : null,
                child: const Text('Clear'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
