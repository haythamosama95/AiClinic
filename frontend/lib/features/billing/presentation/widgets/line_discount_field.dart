import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';

typedef LineDiscountSubmit = Future<bool> Function({required DiscountKind kind, required String value});

typedef LineDiscountClear = Future<bool> Function();

/// Per-line discount input for draft invoices (V1-6 US3).
class LineDiscountField extends StatefulWidget {
  const LineDiscountField({
    super.key,
    required this.item,
    required this.enabled,
    required this.busy,
    required this.onApply,
    required this.onClear,
  });

  final InvoiceItem item;
  final bool enabled;
  final bool busy;
  final LineDiscountSubmit onApply;
  final LineDiscountClear onClear;

  @override
  State<LineDiscountField> createState() => _LineDiscountFieldState();
}

class _LineDiscountFieldState extends State<LineDiscountField> {
  DiscountKind _kind = DiscountKind.percentage;
  final _valueController = TextEditingController();

  @override
  void didUpdateWidget(covariant LineDiscountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _syncFromItem();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncFromItem();
  }

  void _syncFromItem() {
    _kind = widget.item.lineDiscountKind ?? DiscountKind.percentage;
    _valueController.text = widget.item.lineDiscountValue ?? '';
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
    final lineSubtotal = widget.item.lineSubtotal.asDouble;
    if (_kind == DiscountKind.percentage && parsed > 100) {
      return 'Percentage cannot exceed 100.';
    }
    if (_kind == DiscountKind.fixed && parsed > lineSubtotal) {
      return 'Fixed discount cannot exceed the line subtotal.';
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
    final hasDiscount = widget.item.lineDiscountKind != null || widget.item.lineDiscountAmount.isPositive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Line discount', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<DiscountKind>(
                key: Key('line_discount_kind_${widget.item.id}'),
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
                key: Key('line_discount_value_${widget.item.id}'),
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
            child: Text('Applied: ${widget.item.lineDiscountAmount} off (line total ${widget.item.lineTotal})'),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              key: Key('line_discount_apply_${widget.item.id}'),
              onPressed: widget.enabled && !widget.busy ? _submit : null,
              child: const Text('Apply line discount'),
            ),
            if (hasDiscount) ...[
              const SizedBox(width: 8),
              TextButton(
                key: Key('line_discount_clear_${widget.item.id}'),
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
