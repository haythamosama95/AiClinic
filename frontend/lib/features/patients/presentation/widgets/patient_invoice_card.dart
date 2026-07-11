import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_card.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';

/// Invoice record card for the patient detail billing tab (web `InvoiceCard`).
///
/// **Due-date divergence:** The web card shows an Issued / Payment (due date) row.
/// [InvoiceListItem] has no `dueDate` field, so only the Issued line is rendered.
/// [_invoiceDueLabel] is implemented for future `dueDate` binding.
class PatientInvoiceCard extends ConsumerWidget {
  const PatientInvoiceCard({required this.invoice, super.key});

  final InvoiceListItem invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final badgeStyle = statusBadgeStyle(invoice.status);
    final bandColors = _statusBandColors(badgeStyle.variant, colors);
    final displayNumber = invoice.invoiceNumber?.trim().isNotEmpty == true
        ? invoice.invoiceNumber!.trim()
        : PatientPresentationFormatting.displayId(invoice.id);
    final issuedAt = invoice.issuedAt ?? invoice.createdAt;

    final locale = Localizations.localeOf(context).toString();
    final l10n = context.l10n;
    final currencyCode = ref.watch(clinicSetupOrganizationProvider).asData?.value?.currencyCode?.trim();
    final currency = currencyCode != null && currencyCode.isNotEmpty ? currencyCode : 'USD';

    final showInsuranceCoverage =
        !invoice.insuranceCoveredAmount.isZero &&
        !invoice.payments.any((payment) => payment.method == PaymentMethod.insuranceSettlement);
    final showPaidSummary = invoice.payments.isEmpty && !invoice.paidAmount.isZero;
    final showEmptyPayments = invoice.payments.isEmpty && !showPaidSummary && !showInsuranceCoverage;
    final showLedger = invoice.status != InvoiceStatus.draft;

    return PatientRecordCard(
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: bandColors.background,
              border: Border(bottom: BorderSide(color: bandColors.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.mono(
                        context,
                      ).copyWith(color: colors.textSecondary, letterSpacing: 0.08 * 12),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  AppBadge(
                    size: BadgeSize.sm,
                    variant: BadgeVariant.soft,
                    color: _badgeColor(badgeStyle.variant),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeStyle.icon, size: 12),
                        const SizedBox(width: AppSpacing.space1),
                        Text(invoice.status.label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space5,
              AppSpacing.space3,
              AppSpacing.space5,
              AppSpacing.space3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.invoiceBalance,
                            style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
                          ),
                          const SizedBox(height: AppSpacing.space1),
                          Text(
                            BillingFormatting.formatMoney(invoice.balance, currency: currency, locale: locale),
                            style: AppTypography.h2(
                              context,
                            ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.invoiceIssued,
                          style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
                        ),
                        const SizedBox(height: AppSpacing.space1),
                        Text(
                          BillingFormatting.formatDate(issuedAt),
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ],
                ),
                if (showLedger) ...[
                  const SizedBox(height: AppSpacing.space3),
                  Divider(height: 1, thickness: 1, color: colors.borderSubtle.withValues(alpha: 0.8)),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    l10n.invoicePayments,
                    style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  for (final payment in invoice.payments) ...[
                    _InvoicePaymentRow(payment: payment, currency: currency, locale: locale),
                    if (payment != invoice.payments.last || showPaidSummary || showInsuranceCoverage)
                      const SizedBox(height: AppSpacing.space1),
                  ],
                  if (showPaidSummary)
                    _InvoicePaidSummaryRow(amount: invoice.paidAmount, currency: currency, locale: locale),
                  if (showPaidSummary && (showInsuranceCoverage || showEmptyPayments))
                    const SizedBox(height: AppSpacing.space1),
                  if (showInsuranceCoverage)
                    _InvoiceInsuranceRow(amount: invoice.insuranceCoveredAmount, currency: currency, locale: locale),
                  if (showEmptyPayments) _InvoiceEmptyPaymentsRow(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicePaymentRow extends StatelessWidget {
  const _InvoicePaymentRow({required this.payment, required this.currency, required this.locale});

  final Payment payment;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final isRefund = payment.isRefund;
    final amountColor = isRefund ? colors.statusDangerFg : colors.statusSuccessFg;
    final label = isRefund ? l10n.invoicePaymentRefund : payment.method.labelFor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          isRefund ? Icons.undo_outlined : BillingFormatting.paymentMethodIcon(payment.method),
          size: 14,
          color: colors.textTertiary,
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        Text(
          BillingFormatting.formatMoney(payment.amount, currency: currency, locale: locale),
          style: AppTypography.caption(context).copyWith(
            color: amountColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _InvoiceEmptyPaymentsRow extends StatelessWidget {
  const _InvoiceEmptyPaymentsRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Icon(Icons.payments_outlined, size: 14, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            context.l10n.invoiceNoPayments,
            style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _InvoicePaidSummaryRow extends StatelessWidget {
  const _InvoicePaidSummaryRow({required this.amount, required this.currency, required this.locale});

  final Money amount;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 14, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            l10n.invoicePaid,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        Text(
          BillingFormatting.formatMoney(amount, currency: currency, locale: locale),
          style: AppTypography.caption(context).copyWith(
            color: colors.statusSuccessFg,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _InvoiceInsuranceRow extends StatelessWidget {
  const _InvoiceInsuranceRow({required this.amount, required this.currency, required this.locale});

  final Money amount;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.health_and_safety_outlined, size: 14, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            l10n.invoiceInsuranceCovered,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        Text(
          BillingFormatting.formatMoney(amount, currency: currency, locale: locale),
          style: AppTypography.caption(context).copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StatusBandColors {
  const _StatusBandColors({required this.background, required this.border});

  final Color background;
  final Color border;
}

// Reserved for future [InvoiceListItem.dueDate] binding (see class doc comment).
// ignore: unused_element
({String label, bool urgent}) _invoiceDueLabel({
  required DateTime? dueDate,
  required InvoiceStatus status,
  bool overdue = false,
}) {
  if (dueDate == null) {
    return (label: '', urgent: false);
  }

  if (status == InvoiceStatus.paid || status == InvoiceStatus.voided) {
    return (label: 'Due ${PatientPresentationFormatting.date.format(dueDate)}', urgent: false);
  }

  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final diffDays = due.difference(today).inDays;

  if (overdue || diffDays < 0) {
    final overdueDays = diffDays.abs();
    return (label: overdueDays == 1 ? '1 day overdue' : '$overdueDays days overdue', urgent: true);
  }
  if (diffDays == 0) {
    return (label: 'Due today', urgent: true);
  }
  if (diffDays <= 7) {
    return (label: diffDays == 1 ? 'Due tomorrow' : 'Due in $diffDays days', urgent: true);
  }
  return (label: 'Due ${PatientPresentationFormatting.date.format(dueDate)}', urgent: false);
}

_StatusBandColors _statusBandColors(InvoiceStatusBadgeVariant variant, AppSemanticColors colors) {
  return switch (variant) {
    InvoiceStatusBadgeVariant.muted => _StatusBandColors(background: colors.surfaceMuted, border: colors.borderSubtle),
    InvoiceStatusBadgeVariant.primary => _StatusBandColors(
      background: colors.surfaceSelected,
      border: colors.borderSubtle,
    ),
    InvoiceStatusBadgeVariant.accent => _StatusBandColors(
      background: colors.statusWarningSurface,
      border: colors.statusWarningBorder,
    ),
    InvoiceStatusBadgeVariant.success => _StatusBandColors(
      background: colors.statusSuccessSurface,
      border: colors.statusSuccessBorder,
    ),
    InvoiceStatusBadgeVariant.destructive => _StatusBandColors(
      background: colors.statusDangerSurface,
      border: colors.statusDangerBorder,
    ),
  };
}

BadgeColor _badgeColor(InvoiceStatusBadgeVariant variant) {
  return switch (variant) {
    InvoiceStatusBadgeVariant.muted => BadgeColor.neutral,
    InvoiceStatusBadgeVariant.primary => BadgeColor.teal,
    InvoiceStatusBadgeVariant.accent => BadgeColor.warning,
    InvoiceStatusBadgeVariant.success => BadgeColor.success,
    InvoiceStatusBadgeVariant.destructive => BadgeColor.danger,
  };
}
