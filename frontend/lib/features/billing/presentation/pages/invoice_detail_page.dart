import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/void_invoice_dialog.dart';

/// Invoice detail surface (`/billing/invoices/:id`).
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(invoiceDetailViewProvider(invoiceId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: 'Could not load invoice',
          description: error.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onPressed: () => ref.invalidate(invoiceDetailViewProvider(invoiceId)),
          ),
        ),
      ),
      data: (view) => _InvoiceDetailBody(view: view),
    );
  }
}

class _InvoiceDetailBody extends ConsumerStatefulWidget {
  const _InvoiceDetailBody({required this.view});

  final InvoiceDetailViewState view;

  @override
  ConsumerState<_InvoiceDetailBody> createState() => _InvoiceDetailBodyState();
}

class _InvoiceDetailBodyState extends ConsumerState<_InvoiceDetailBody> {
  var _showPaymentForm = false;
  var _showRefundForm = false;

  InvoiceDetail get invoice => widget.view.invoice;

  void _refresh() {
    ref.invalidate(invoiceDetailViewProvider(invoice.id));
    ref.invalidate(invoiceListProvider);
  }

  Future<void> _voidInvoice() async {
    final confirmed = await VoidInvoiceDialog.show(context, invoice: invoice);
    if (confirmed && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final netTotal = invoice.subtotal - invoice.discountAmount;
    final canEdit = invoice.status.isDraft && widget.view.canCreate;
    final canPay = widget.view.canRecordPayment && !invoice.status.isDraft && !invoice.status.isTerminal;
    final canVoid = widget.view.canVoid && invoice.status.isVoidable;
    final canRefund = widget.view.canRefund && invoice.payments.any((payment) => !payment.isRefund);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: displayNumber,
            description: [
              if (invoice.patientDisplayName?.isNotEmpty == true) invoice.patientDisplayName,
              if (invoice.branchName?.isNotEmpty == true) invoice.branchName,
              if (invoice.issuedAt != null) 'Issued ${BillingFormatting.formatDate(invoice.issuedAt!)}',
            ].whereType<String>().join(' · '),
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canEdit)
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    leadingIcon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => context.nav.pushBillingInvoiceEdit(invoice.id),
                    child: const Text('Edit draft'),
                  ),
                if (canEdit && canVoid) const SizedBox(width: AppSpacing.space2),
                if (canVoid)
                  AppButton(variant: AppButtonVariant.danger, onPressed: _voidInvoice, child: const Text('Void')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Row(
            children: [
              InvoiceStatusBadge(status: invoice.status, size: BadgeSize.md),
              if (!invoice.balance.isZero && !invoice.status.isDraft) ...[
                const SizedBox(width: AppSpacing.space4),
                Text(
                  'Balance ${BillingFormatting.formatMoney(invoice.balance, currency: invoice.currency)}',
                  style: AppTypography.bodyStrong(context).copyWith(color: colors.statusWarningFg),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              borderRadius: BorderRadius.circular(AppRadius.x2l),
              border: Border.all(color: colors.borderSubtle),
              boxShadow: elevation?.shadows1 ?? AppElevation.level1,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LineItemsTable(items: invoice.items, currency: invoice.currency),
                  const InvoicePerforationDivider(),
                  _TotalsPanel(
                    subtotal: invoice.subtotal,
                    discount: invoice.discountAmount,
                    insurance: invoice.insuranceCoveredAmount,
                    total: netTotal,
                    balance: invoice.balance,
                    currency: invoice.currency,
                    showBalance: !invoice.status.isDraft,
                  ),
                ],
              ),
            ),
          ),
          if (invoice.payments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space5),
            Text('Payment ledger', style: AppTypography.bodyStrong(context)),
            const SizedBox(height: AppSpacing.space3),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceDefault,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                children: [
                  for (final payment in invoice.payments)
                    _PaymentLedgerRow(payment: payment, currency: invoice.currency),
                ],
              ),
            ),
          ],
          if (canPay || canRefund) ...[
            const SizedBox(height: AppSpacing.space5),
            if (canPay) ...[
              if (!_showPaymentForm)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    leadingIcon: const Icon(Icons.payments_outlined, size: 16),
                    onPressed: () => setState(() {
                      _showPaymentForm = true;
                      _showRefundForm = false;
                    }),
                    child: const Text('Record payment'),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space5),
                    child: PaymentForm(
                      invoice: invoice,
                      onRecorded: () {
                        setState(() => _showPaymentForm = false);
                        _refresh();
                      },
                    ),
                  ),
                ),
            ],
            if (canRefund) ...[
              const SizedBox(height: AppSpacing.space3),
              if (!_showRefundForm)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => setState(() {
                      _showRefundForm = true;
                      _showPaymentForm = false;
                    }),
                    child: const Text('Record refund'),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space5),
                    child: RefundForm(
                      invoice: invoice,
                      onRecorded: () {
                        setState(() => _showRefundForm = false);
                        _refresh();
                      },
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LineItemsTable extends StatelessWidget {
  const _LineItemsTable({required this.items, required this.currency});

  final List<InvoiceItem> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (items.isEmpty) {
      return Text('No line items', style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary));
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 5, child: _HeaderCell('Service')),
            Expanded(flex: 2, child: _HeaderCell('Qty', align: TextAlign.end)),
            Expanded(flex: 3, child: _HeaderCell('Unit', align: TextAlign.end)),
            Expanded(flex: 3, child: _HeaderCell('Total', align: TextAlign.end)),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        for (final item in items) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: Text(item.description, style: AppTypography.body(context))),
                Expanded(
                  flex: 2,
                  child: Text(item.quantity, textAlign: TextAlign.end, style: AppTypography.bodySm(context)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    BillingFormatting.formatMoney(item.unitPrice, currency: currency),
                    textAlign: TextAlign.end,
                    style: AppTypography.bodySm(context),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    BillingFormatting.formatMoney(item.lineTotal, currency: currency),
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyStrong(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: align,
      style: AppTypography.caption(
        context,
      ).copyWith(color: context.appColors.textTertiary, letterSpacing: 0.08, fontWeight: FontWeight.w600),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({
    required this.subtotal,
    required this.discount,
    required this.insurance,
    required this.total,
    required this.balance,
    required this.currency,
    required this.showBalance,
  });

  final Money subtotal;
  final Money discount;
  final Money insurance;
  final Money total;
  final Money balance;
  final String currency;
  final bool showBalance;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TotalRow(
          label: 'Subtotal',
          value: BillingFormatting.formatMoney(subtotal, currency: currency),
        ),
        if (!discount.isZero)
          _TotalRow(
            label: 'Discount',
            value: '- ${BillingFormatting.formatMoney(discount, currency: currency)}',
            valueColor: context.appColors.statusSuccessFg,
          ),
        if (!insurance.isZero)
          _TotalRow(
            label: 'Insurance',
            value: BillingFormatting.formatMoney(insurance, currency: currency),
          ),
        const SizedBox(height: AppSpacing.space2),
        _TotalRow(
          label: 'Total',
          value: BillingFormatting.formatMoney(total, currency: currency),
          emphasized: true,
        ),
        if (showBalance && !balance.isZero)
          _TotalRow(
            label: 'Balance due',
            value: BillingFormatting.formatMoney(balance, currency: currency),
            emphasized: true,
            valueColor: context.appColors.statusWarningFg,
          ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.emphasized = false, this.valueColor});

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelStyle = emphasized
        ? AppTypography.bodyStrong(context)
        : AppTypography.bodySm(context).copyWith(color: colors.textSecondary);
    final valueStyle = emphasized
        ? AppTypography.bodyStrong(context).copyWith(color: valueColor ?? colors.textPrimary)
        : AppTypography.bodySm(context).copyWith(color: valueColor ?? colors.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _PaymentLedgerRow extends StatelessWidget {
  const _PaymentLedgerRow({required this.payment, required this.currency});

  final Payment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
      child: Row(
        children: [
          Icon(BillingFormatting.paymentMethodIcon(payment.method), size: 16, color: colors.iconMuted),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.isRefund ? 'Refund' : payment.method.labelFor(context),
                  style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  BillingFormatting.formatDateTime(payment.recordedAt),
                  style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            BillingFormatting.formatMoney(payment.amount, currency: currency),
            style: AppTypography.bodyStrong(
              context,
            ).copyWith(color: payment.isRefund ? colors.statusDangerFg : colors.statusSuccessFg),
          ),
        ],
      ),
    );
  }
}
