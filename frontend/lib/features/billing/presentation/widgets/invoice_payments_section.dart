import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_action_button.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_record_dialog.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_record_dialog.dart';

/// Payments history and payment/refund actions on invoice detail.
class InvoicePaymentsSection extends ConsumerWidget {
  const InvoicePaymentsSection({
    required this.invoice,
    required this.canRecordPayment,
    required this.canRefund,
    required this.onChanged,
    super.key,
  });

  final InvoiceDetail invoice;
  final bool canRecordPayment;
  final bool canRefund;
  final VoidCallback onChanged;

  bool get _canRecordNow =>
      canRecordPayment &&
      !invoice.status.isVoided &&
      !invoice.status.isDraft &&
      !invoice.balance.isZero;

  bool get _canRefundNow =>
      canRefund && !invoice.status.isVoided && invoice.payments.any((payment) => !payment.isRefund);

  String? get _recordDisabledReason {
    if (!canRecordPayment) {
      return 'You do not have permission to record payments.';
    }
    if (invoice.status.isVoided) {
      return 'This invoice is voided and cannot accept payments.';
    }
    if (invoice.status.isDraft) {
      return 'Issue the invoice before recording payments.';
    }
    if (invoice.balance.isZero) {
      return 'This invoice is fully paid.';
    }
    return null;
  }

  String? get _refundDisabledReason {
    if (!canRefund) {
      return 'You do not have permission to record refunds.';
    }
    if (invoice.status.isVoided) {
      return 'Refunds cannot be recorded on voided invoices.';
    }
    if (!invoice.payments.any((payment) => !payment.isRefund)) {
      return 'Record a payment before issuing a refund.';
    }
    return null;
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final recorded = await showPaymentRecordDialog(context: context, ref: ref, invoice: invoice);
    if (recorded) {
      ref.showAppToast(message: 'Payment recorded.', variant: AppToastVariant.success);
      onChanged();
    }
  }

  Future<void> _recordRefund(BuildContext context, WidgetRef ref) async {
    final recorded = await showRefundRecordDialog(context: context, ref: ref, invoice: invoice);
    if (recorded) {
      ref.showAppToast(message: 'Refund recorded.', variant: AppToastVariant.success);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = context.typography;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Payments',
                style: typography.title.copyWith(color: colors.textPrimary),
              ),
            ),
            if (canRecordPayment || _recordDisabledReason != null) ...[
              BillingActionButton(
                disabledReason: _recordDisabledReason,
                child: AppButton(
                  label: 'Record payment',
                  size: AppButtonSize.sm,
                  leadingIcon: LucideIcons.banknote,
                  disabled: !_canRecordNow,
                  onPressed: _canRecordNow ? () => _recordPayment(context, ref) : null,
                ),
              ),
            ],
            if (canRefund || _refundDisabledReason != null) ...[
              const SizedBox(width: AppSpacing.s2),
              BillingActionButton(
                disabledReason: _refundDisabledReason,
                child: AppButton(
                  label: 'Record refund',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  leadingIcon: LucideIcons.rotateCcw,
                  disabled: !_canRefundNow,
                  onPressed: _canRefundNow ? () => _recordRefund(context, ref) : null,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        if (invoice.payments.isEmpty)
          const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No payments recorded yet',
            description: 'Payments and refunds will appear here once recorded.',
          )
        else
          AppCard(
            variant: AppCardVariant.flat,
            padding: AppCardPadding.sm,
            child: Column(
              children: [
                for (final payment in invoice.payments) ...[
                  _PaymentRow(payment: payment, currency: invoice.currency),
                  if (payment != invoice.payments.last)
                    Divider(height: 1, color: colors.borderSubtle),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.currency});

  final Payment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final title = payment.isRefund ? 'Refund' : 'Payment';

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title · ${payment.method.label}',
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  BillingFormatting.formatDateTime(payment.recordedAt),
                  style: typography.tabular(typography.bodySm).copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (payment.reference != null && payment.reference!.isNotEmpty)
                  Text(
                    'Ref: ${payment.reference}',
                    style: typography.bodySm.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (payment.note != null && payment.note!.isNotEmpty)
                  Text(
                    payment.note!,
                    style: typography.bodySm.copyWith(color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (payment.recordedByDisplayName != null)
                  Text(
                    'Recorded by ${payment.recordedByDisplayName}',
                    style: typography.caption.copyWith(color: colors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          AppMoney(
            amount: Decimal.parse(payment.amount.wireValue),
            currency: currency,
            isRefund: payment.isRefund,
            emphasis: AppMoneyEmphasis.strong,
          ),
        ],
      ),
    );
  }
}
