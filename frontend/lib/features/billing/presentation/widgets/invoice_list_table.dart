import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

InvoiceCardStatus invoiceCardStatusFor(InvoiceStatus status) {
  return switch (status) {
    InvoiceStatus.paid => InvoiceCardStatus.paid,
    InvoiceStatus.voided => InvoiceCardStatus.overdue,
    _ => InvoiceCardStatus.pending,
  };
}

List<AppTableColumn<InvoiceListItem>> buildInvoiceTableColumns(BuildContext context) {
  final typography = context.typography;
  final colors = context.colors;

  return [
    AppTableColumn(
      id: 'invoice',
      header: 'Invoice',
      cellBuilder: (context, item) => Text(
        BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id),
        style: typography.bodyStrong.copyWith(color: colors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    AppTableColumn(
      id: 'patient',
      header: 'Patient',
      cellBuilder: (context, item) => Text(
        item.patientDisplayName ?? '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    AppTableColumn(
      id: 'status',
      header: 'Status',
      width: 148,
      cellBuilder: (context, item) => InvoiceStatusBadge(status: item.status, dense: true),
    ),
    AppTableColumn(
      id: 'total',
      header: 'Total',
      align: AppTableColumnAlign.end,
      width: 120,
      cellBuilder: (context, item) => AppMoney(
        amount: Decimal.parse(item.displayTotal),
        emphasis: AppMoneyEmphasis.normal,
      ),
    ),
    AppTableColumn(
      id: 'paid',
      header: 'Paid',
      align: AppTableColumnAlign.end,
      width: 120,
      cellBuilder: (context, item) => AppMoney(amount: Decimal.parse(item.paidAmount.wireValue)),
    ),
    AppTableColumn(
      id: 'balance',
      header: 'Balance',
      align: AppTableColumnAlign.end,
      width: 120,
      cellBuilder: (context, item) => AppMoney(
        amount: Decimal.parse(item.balance.wireValue),
        emphasis: item.balance.isZero ? AppMoneyEmphasis.normal : AppMoneyEmphasis.strong,
      ),
    ),
    AppTableColumn(
      id: 'date',
      header: 'Date',
      width: 132,
      cellBuilder: (context, item) => Text(
        BillingFormatting.formatDate(item.issuedAt ?? item.createdAt),
        style: typography.tabular(typography.bodySm),
      ),
    ),
  ];
}

/// Compact card list for narrow invoice list layouts.
class InvoiceListCards extends StatelessWidget {
  const InvoiceListCards({
    required this.items,
    required this.onItemTap,
    super.key,
  });

  final List<InvoiceListItem> items;
  final ValueChanged<InvoiceListItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s2),
      itemBuilder: (context, index) {
        final item = items[index];
        final date = BillingFormatting.formatDate(item.issuedAt ?? item.createdAt);
        return AppPressable(
          onTap: () => onItemTap(item),
          borderRadius: AppRadii.mdAll,
          semanticLabel: 'Open invoice',
          child: InvoiceCard(
            number: BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id),
            patient: item.patientDisplayName ?? '—',
            amount: double.parse(item.displayTotal),
            status: invoiceCardStatusFor(item.status),
            date: date,
          ),
        );
      },
    );
  }
}
