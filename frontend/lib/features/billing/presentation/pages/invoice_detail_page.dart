import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_action_button.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_payments_section.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/void_invoice_dialog.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Issued invoice detail — totals, payments, receipt print, and void (V1-6).
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({
    required this.invoiceId,
    super.key,
  });

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceDetail(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Invoice',
        description: 'You do not have permission to view invoices.',
      );
    }

    final id = invoiceId.trim();
    if (id.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Invoice not found',
        description: 'A valid invoice id is required.',
      );
    }

    final viewAsync = ref.watch(invoiceDetailViewProvider(id));

    return viewAsync.when(
      loading: () => const RecordDetailPattern(
        title: 'Invoice',
        body: Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Invoice',
        body: AppErrorState(
          message: error is RpcFailure ? billingMessageForRpc(error) : error.toString(),
          onRetry: () => ref.invalidate(invoiceDetailViewProvider(id)),
        ),
      ),
      data: (view) {
        if (view.invoice.status == InvoiceStatus.draft && view.canCreate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.billingInvoiceEdit(id));
            }
          });
          return const RecordDetailPattern(
            title: 'Invoice',
            body: Center(child: AppSpinner()),
          );
        }
        return _InvoiceDetailBody(invoiceId: id, view: view);
      },
    );
  }
}

class _InvoiceDetailBody extends ConsumerWidget {
  const _InvoiceDetailBody({required this.invoiceId, required this.view});

  final String invoiceId;
  final InvoiceDetailViewState view;

  String? _voidDisabledReason() {
    if (!view.canVoid) {
      return 'You do not have permission to void invoices.';
    }
    if (!view.invoice.status.isVoidable) {
      if (view.invoice.status == InvoiceStatus.paid) {
        return 'Refund paid invoices before voiding.';
      }
      return 'Only issued or partially paid invoices can be voided.';
    }
    return null;
  }

  bool get _canVoidNow => view.canVoid && view.invoice.status.isVoidable;

  Future<void> _voidInvoice(BuildContext context, WidgetRef ref) async {
    final voided = await showVoidInvoiceDialog(context: context, ref: ref, invoice: view.invoice);
    if (voided) {
      ref.invalidate(invoiceDetailViewProvider(invoiceId));
      ref.showAppToast(message: 'Invoice voided.', variant: AppToastVariant.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = view.invoice;
    final orgName = ref.watch(clinicSetupOrganizationProvider).maybeWhen(data: (org) => org?.name, orElse: () => null);
    final title = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);

    return RecordDetailPattern(
      title: title,
      description: invoice.patientDisplayName ?? invoice.patientId,
      statusBadge: InvoiceStatusBadge(status: invoice.status),
      actions: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          ReceiptPrintActions(detail: invoice, organizationName: orgName),
          if (view.canVoid || _voidDisabledReason() != null)
            BillingActionButton(
              disabledReason: _voidDisabledReason(),
              child: AppButton(
                key: const Key('invoice_void_button'),
                label: 'Void invoice',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.danger,
                leadingIcon: LucideIcons.ban,
                disabled: !_canVoidNow,
                onPressed: _canVoidNow ? () => _voidInvoice(context, ref) : null,
              ),
            ),
          if (view.canCreate && invoice.status.isDraft)
            AppButton(
              label: 'Edit draft',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.secondary,
              leadingIcon: LucideIcons.pencil,
              onPressed: () => context.push(AppRoutes.billingInvoiceEdit(invoiceId)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDescriptionList(
              items: [
                AppDescriptionItem(
                  label: 'Patient',
                  value: Text(invoice.patientDisplayName ?? invoice.patientId),
                ),
                if (invoice.branchName != null)
                  AppDescriptionItem(label: 'Branch', value: Text(invoice.branchName!)),
                if (invoice.issuedAt != null)
                  AppDescriptionItem(
                    label: 'Issued',
                    value: Text(BillingFormatting.formatDateTime(invoice.issuedAt!)),
                  ),
              ],
            ),
            if (invoice.status.isVoided && invoice.voidReason != null) ...[
              const SizedBox(height: AppSpacing.s3),
              AppAlert(
                key: const Key('invoice_void_reason_banner'),
                variant: AppAlertVariant.danger,
                title: 'Voided',
                body: invoice.voidReason,
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            Text('Line items', style: context.typography.title),
            const SizedBox(height: AppSpacing.s3),
            if (invoice.items.isEmpty)
              const AppEmptyState(
                variant: AppEmptyStateVariant.noResults,
                title: 'No line items',
                description: 'This invoice has no line items.',
              )
            else
              AppCard(
                variant: AppCardVariant.flat,
                padding: AppCardPadding.sm,
                child: Column(
                  children: [
                    for (final item in invoice.items) ...[
                      _InvoiceItemRow(item: item, currency: invoice.currency),
                      if (item != invoice.items.last)
                        Divider(height: 1, color: context.colors.borderSubtle),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s4),
            InvoiceTotalsPanel(invoice: invoice),
            const SizedBox(height: AppSpacing.s4),
            InvoicePaymentsSection(
              invoice: invoice,
              canRecordPayment: view.canRecordPayment,
              canRefund: view.canRefund,
              onChanged: () => ref.invalidate(invoiceDetailViewProvider(invoiceId)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemRow extends StatelessWidget {
  const _InvoiceItemRow({required this.item, required this.currency});

  final InvoiceItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${item.quantity} × ${item.unitPrice.wireValue}',
                  style: typography.tabular(typography.bodySm).copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!item.lineDiscountAmount.isZero)
                  Text(
                    'Line discount: ${item.lineDiscountAmount.wireValue}',
                    style: typography.bodySm.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          AppMoney(
            amount: Decimal.parse(item.lineTotal.wireValue),
            currency: currency,
            emphasis: AppMoneyEmphasis.strong,
          ),
        ],
      ),
    );
  }
}
