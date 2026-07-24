import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

/// Invoices ledger table backed by [AppDataTable].
class InvoiceLedgerTable extends StatelessWidget {
  const InvoiceLedgerTable({
    required this.items,
    this.loading = false,
    this.loadingRows = 10,
    this.onRowClick,
    this.emptyState,
    this.errorState,
    super.key,
  });

  final List<InvoiceListItem> items;
  final bool loading;
  final int loadingRows;
  final ValueChanged<InvoiceListItem>? onRowClick;
  final Widget? emptyState;
  final Widget? errorState;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  /// Badge sm horizontal padding (6×2) + icon (12) + gap + longest label + cell padding + margin.
  static double _statusColumnWidth(BuildContext context) {
    final textStyle = AppTypography.caption(
      context,
    ).copyWith(fontWeight: FontWeight.w500);
    var maxLabelWidth = 0.0;
    for (final status in InvoiceStatus.values) {
      final painter = TextPainter(
        text: TextSpan(text: status.label, style: textStyle),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      maxLabelWidth = math.max(maxLabelWidth, painter.width);
    }

    const badgeHorizontalPadding = 12.0;
    const iconWidth = 12.0;
    const iconGap = AppSpacing.space1;
    const cellHorizontalPadding = AppSpacing.space3 * 2;
    const endMargin = AppSpacing.space2;

    return badgeHorizontalPadding +
        iconWidth +
        iconGap +
        maxLabelWidth.ceilToDouble() +
        cellHorizontalPadding +
        endMargin;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppDataTable<InvoiceListItem>(
      ariaLabel: 'Invoices',
      animateRows: true,
      density: TableDensity.comfortable,
      headerTextStyle: AppTypography.caption(
        context,
      ).copyWith(fontWeight: FontWeight.w600, color: colors.textTertiary),
      columns: [
        TableColumn(
          id: 'number',
          header: 'Invoice',
          accessor: (item) => _InvoiceNumberCell(item: item),
        ),
        TableColumn(
          id: 'patient',
          header: 'Patient',
          accessor: (item) => _PatientCell(item: item),
        ),
        TableColumn(
          id: 'status',
          header: 'Status',
          width: _statusColumnWidth(context),
          accessor: (item) =>
              InvoiceStatusBadge(status: item.status, size: BadgeSize.sm),
        ),
        TableColumn(
          id: 'subtotal',
          header: 'Subtotal',
          align: TableAlign.end,
          accessor: (item) => DefaultTextStyle.merge(
            style: AppTypography.bodySm(
              context,
            ).copyWith(fontFeatures: _tabularFigures),
            child: AppMoneyDisplay(
              amount: item.subtotal.asDouble,
              currency: item.currency,
            ),
          ),
        ),
        TableColumn(
          id: 'payments',
          header: 'Total payments',
          align: TableAlign.end,
          accessor: (item) => DefaultTextStyle.merge(
            style: AppTypography.bodySm(context).copyWith(
              color: item.paidAmount.asDouble <= 0
                  ? colors.textTertiary
                  : colors.textSecondary,
              fontFeatures: _tabularFigures,
            ),
            child: AppMoneyDisplay(
              amount: item.paidAmount.asDouble,
              currency: item.currency,
              negative: false,
            ),
          ),
        ),
        TableColumn(
          id: 'remaining',
          header: 'Remaining',
          align: TableAlign.end,
          accessor: (item) => _RemainingCell(item: item),
        ),
      ],
      data: items,
      getRowId: (item) => item.id,
      loading: loading,
      loadingRows: loadingRows,
      emptyState: emptyState,
      errorState: errorState,
      onRowClick:
          onRowClick ?? (item) => context.nav.pushBillingInvoiceDetail(item.id),
    );
  }
}

class _InvoiceNumberCell extends StatelessWidget {
  const _InvoiceNumberCell({required this.item});

  final InvoiceListItem item;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displayNumber = BillingFormatting.invoiceDisplayNumber(
      item.invoiceNumber,
      item.id,
    );
    final issuedAt = item.issuedAt ?? item.createdAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayNumber,
          style: AppTypography.mono(context).copyWith(
            color: colors.textPrimary,
            letterSpacing: 0.04 * 13,
            fontFeatures: _tabularFigures,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          BillingFormatting.formatDate(issuedAt),
          style: AppTypography.caption(
            context,
          ).copyWith(color: colors.textTertiary, fontFeatures: _tabularFigures),
        ),
      ],
    );
  }
}

class _PatientCell extends StatelessWidget {
  const _PatientCell({required this.item});

  final InvoiceListItem item;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final patientName = item.patientDisplayName?.trim().isNotEmpty == true
        ? item.patientDisplayName!.trim()
        : 'Patient';

    return Row(
      children: [
        AppAvatar(name: patientName, size: AvatarSize.sm),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                patientName,
                style: AppTypography.bodyStrong(
                  context,
                ).copyWith(color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                item.patientMrn ?? '—',
                style: AppTypography.caption(context).copyWith(
                  color: colors.textTertiary,
                  fontFeatures: _tabularFigures,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemainingCell extends StatelessWidget {
  const _RemainingCell({required this.item});

  final InvoiceListItem item;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final balance = item.balance.asDouble;
    final isVoided = item.status == InvoiceStatus.voided;
    final isPaidGreen = balance <= 0 && !isVoided;

    return DefaultTextStyle.merge(
      style: AppTypography.bodySm(context).copyWith(
        color: isVoided
            ? colors.textTertiary
            : isPaidGreen
            ? colors.statusSuccessFg
            : null,
        fontFeatures: _tabularFigures,
      ),
      child: AppMoneyDisplay(
        amount: balance,
        currency: item.currency,
        emphasis: balance > 0 && !isVoided,
        negative: balance < 0,
      ),
    );
  }
}
