import 'package:flutter/material.dart';

import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_discount_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/line_discount_field.dart';

typedef LineDiscountApply =
    Future<bool> Function({required String itemId, required DiscountKind kind, required String value});

typedef LineDiscountClearItem = Future<bool> Function({required String itemId});

typedef InvoiceDiscountApply = Future<bool> Function({required DiscountKind kind, required String value});

typedef InvoiceDiscountClear = Future<bool> Function();

bool invoiceHasLineDiscountScope(InvoiceDetail detail) {
  return detail.items.any((item) => item.lineDiscountKind != null || item.lineDiscountAmount.isPositive);
}

bool invoiceHasInvoiceDiscountScope(InvoiceDetail detail) {
  final hasValue = detail.discountValue != null && (double.tryParse(detail.discountValue!) ?? 0) > 0;
  return detail.discountAmount.isPositive || (detail.discountKind != null && hasValue);
}

/// Enforces mutually-exclusive line vs invoice discount UX (V1-6 US3).
class DiscountScopeGuard extends StatelessWidget {
  const DiscountScopeGuard({
    super.key,
    required this.detail,
    required this.canApplyDiscount,
    required this.busy,
    required this.onApplyLineDiscount,
    required this.onClearLineDiscount,
    required this.onApplyInvoiceDiscount,
    required this.onClearInvoiceDiscount,
    required this.onClearAllLineDiscounts,
  });

  final InvoiceDetail detail;
  final bool canApplyDiscount;
  final bool busy;
  final LineDiscountApply onApplyLineDiscount;
  final LineDiscountClearItem onClearLineDiscount;
  final InvoiceDiscountApply onApplyInvoiceDiscount;
  final InvoiceDiscountClear onClearInvoiceDiscount;
  final Future<bool> Function() onClearAllLineDiscounts;

  @override
  Widget build(BuildContext context) {
    if (!canApplyDiscount) {
      return const SizedBox.shrink();
    }

    final lineScopeActive = invoiceHasLineDiscountScope(detail);
    final invoiceScopeActive = invoiceHasInvoiceDiscountScope(detail);
    final lineInputsEnabled = !invoiceScopeActive;
    final invoiceInputsEnabled = !lineScopeActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Discounts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (lineScopeActive && invoiceScopeActive)
          MaterialBanner(
            key: const Key('discount_scope_conflict_banner'),
            content: const Text('Discount scopes are mutually exclusive. Clear one scope before using the other.'),
            actions: [
              TextButton(
                key: const Key('discount_clear_line_scope'),
                onPressed: busy ? null : onClearAllLineDiscounts,
                child: const Text('Clear line discounts'),
              ),
              TextButton(
                key: const Key('discount_clear_invoice_scope'),
                onPressed: busy ? null : onClearInvoiceDiscount,
                child: const Text('Clear invoice discount'),
              ),
            ],
          )
        else if (lineScopeActive)
          _ScopeNotice(
            key: const Key('discount_line_scope_active'),
            scope: DiscountScope.line,
            onClearOther: onClearAllLineDiscounts,
            busy: busy,
          )
        else if (invoiceScopeActive)
          _ScopeNotice(
            key: const Key('discount_invoice_scope_active'),
            scope: DiscountScope.invoice,
            onClearOther: onClearInvoiceDiscount,
            busy: busy,
          ),
        const SizedBox(height: 12),
        if (detail.items.isNotEmpty) ...[
          Text('Line-level', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...detail.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LineDiscountField(
                key: Key('line_discount_field_${item.id}'),
                item: item,
                enabled: lineInputsEnabled,
                busy: busy,
                onApply: ({required kind, required value}) =>
                    onApplyLineDiscount(itemId: item.id, kind: kind, value: value),
                onClear: () => onClearLineDiscount(itemId: item.id),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        InvoiceDiscountPanel(
          detail: detail,
          enabled: invoiceInputsEnabled,
          busy: busy,
          onApply: onApplyInvoiceDiscount,
          onClear: onClearInvoiceDiscount,
        ),
      ],
    );
  }
}

class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice({super.key, required this.scope, required this.onClearOther, required this.busy});

  final DiscountScope scope;
  final Future<bool> Function() onClearOther;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final message = switch (scope) {
      DiscountScope.line => 'Line-level discounts are active. Clear them before applying an invoice-level discount.',
      DiscountScope.invoice => 'An invoice-level discount is active. Clear it before applying line-level discounts.',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(message)),
        TextButton(
          key: Key('discount_clear_other_scope_${scope.name}'),
          onPressed: busy ? null : onClearOther,
          child: const Text('Clear other scope'),
        ),
      ],
    );
  }
}
