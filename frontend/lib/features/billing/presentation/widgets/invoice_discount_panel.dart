import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/discount_scope_guard.dart';

/// Invoice-level discount panel for draft invoices (V1-6 US3).
class InvoiceDiscountPanel extends StatefulWidget {
  const InvoiceDiscountPanel({
    required this.invoice,
    required this.enabled,
    required this.activeScope,
    required this.onApply,
    required this.onClearScope,
    super.key,
  });

  final InvoiceDetail invoice;
  final bool enabled;
  final DiscountScope? activeScope;
  final Future<void> Function(DiscountKind? kind, String? value) onApply;
  final Future<void> Function() onClearScope;

  @override
  State<InvoiceDiscountPanel> createState() => _InvoiceDiscountPanelState();
}

class _InvoiceDiscountPanelState extends State<InvoiceDiscountPanel> {
  DiscountKind _kind = DiscountKind.percentage;
  final _valueController = TextEditingController();
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncFromInvoice();
  }

  @override
  void didUpdateWidget(InvoiceDiscountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.discountKind != widget.invoice.discountKind) {
      _syncFromInvoice();
    }
  }

  void _syncFromInvoice() {
    _kind = widget.invoice.discountKind ?? DiscountKind.percentage;
    _valueController.text = widget.invoice.discountValue ?? '';
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  bool get _blocked => widget.activeScope == DiscountScope.line;

  Future<void> _apply() async {
    setState(() => _isSaving = true);
    try {
      final value = _valueController.text.trim();
      await widget.onApply(value.isEmpty ? null : _kind, value.isEmpty ? null : value);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _isSaving = true);
    try {
      await widget.onApply(null, null);
      _valueController.clear();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeBlocked = _blocked && widget.enabled;
    final currency = widget.invoice.currency;

    return AppCard(
      title: const Text('Invoice discount'),
      description: const Text('Apply a single discount to the entire invoice subtotal.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiscountScopeGuard(
            activeScope: widget.activeScope,
            blockedScope: DiscountScope.invoice,
            onClearActiveScope: scopeBlocked ? () => widget.onClearScope() : null,
          ),
          if (scopeBlocked) const SizedBox(height: SpacingTokens.md),
          Opacity(
            opacity: scopeBlocked || !widget.enabled ? 0.5 : 1,
            child: IgnorePointer(
              ignoring: scopeBlocked || !widget.enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSelectTileGroup<DiscountKind>(
                    mode: AppSelectGroupMode.radio,
                    options: [for (final kind in DiscountKind.values) AppSelectOption(value: kind, label: kind.label)],
                    values: {_kind},
                    onChanged: (values) {
                      if (values.isNotEmpty) {
                        setState(() => _kind = values.first);
                      }
                    },
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppTextField(
                    controller: _valueController,
                    label: 'Discount value',
                    hintText: _kind == DiscountKind.percentage ? '0–100%' : 'Fixed amount',
                  ),
                  if (!widget.invoice.discountAmount.isZero) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      'Applied: -${BillingFormatting.formatMoney(widget.invoice.discountAmount, currency: currency)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: SpacingTokens.md),
                  Row(
                    children: [
                      AppButton(label: 'Apply discount', isLoading: _isSaving, expand: false, onPressed: _apply),
                      if (!widget.invoice.discountAmount.isZero) ...[
                        const SizedBox(width: SpacingTokens.sm),
                        AppButton(label: 'Clear', variant: AppButtonVariant.ghost, expand: false, onPressed: _clear),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
