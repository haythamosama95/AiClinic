import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/void_invoice_dialog.dart';

/// Issued/paid/voided invoice detail with payments panel (V1-6 US2/US6/US7).
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceDetail(auth)) {
      return const Scaffold(body: Center(child: Text('You do not have permission to view invoices.')));
    }

    final detailAsync = ref.watch(invoiceDetailViewProvider(invoiceId));
    final settingsAsync = ref.watch(billingSettingsProvider);

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => const AppFullPageLoading(message: 'Loading invoice…'),
      error: (error, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Unable to load invoice: $error'),
              const SizedBox(height: SpacingTokens.md),
              AppButton(
                label: 'Retry',
                expand: false,
                onPressed: () => ref.invalidate(invoiceDetailViewProvider(invoiceId)),
              ),
            ],
          ),
        ),
      ),
      data: (view) {
        if (view.invoice.status.isDraft) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.billingInvoiceEdit(invoiceId));
            }
          });
          return const AppFullPageLoading(message: 'Opening editor…');
        }

        final allowPartial = settingsAsync.value?.allowPartialPayments ?? false;
        return _InvoiceDetailScaffold(
          view: view,
          allowPartialPayments: allowPartial,
          onRefresh: () {
            ref.invalidate(invoiceDetailViewProvider(invoiceId));
            ref.invalidate(billingSettingsProvider);
          },
          onPrint: () => ReceiptPrintPreview.show(context, view.invoice),
          onVoid: () => _voidInvoice(context, ref, view.invoice.updatedAt),
          onRecordPayment: (method, amount, reference, note) =>
              _recordPayment(context, ref, method, amount, reference, note),
          onRecordRefund: (method, amount, note) => _recordRefund(context, ref, method, amount, note),
        );
      },
    );
  }

  Future<void> _voidInvoice(BuildContext context, WidgetRef ref, DateTime expectedUpdatedAt) async {
    final reason = await VoidInvoiceDialog.show(context);
    if (reason == null || !context.mounted) return;

    try {
      await ref
          .read(invoiceRepositoryProvider)
          .voidInvoice(invoiceId: invoiceId, expectedUpdatedAt: expectedUpdatedAt, reason: reason);
      if (!context.mounted) return;
      AppToast.success(context, message: 'Invoice voided.');
      ref.invalidate(invoiceDetailViewProvider(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: billingMessageForRpc(error));
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    PaymentMethod method,
    String amount,
    String? reference,
    String? note,
  ) async {
    try {
      await ref
          .read(paymentNotifierProvider)
          .recordPayment(invoiceId: invoiceId, method: method, amount: amount, reference: reference, note: note);
      if (!context.mounted) return;
      AppToast.success(context, message: 'Payment recorded.');
      ref.invalidate(invoiceDetailViewProvider(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: billingMessageForRpc(error));
    }
  }

  Future<void> _recordRefund(
    BuildContext context,
    WidgetRef ref,
    PaymentMethod method,
    String amount,
    String note,
  ) async {
    try {
      await ref
          .read(paymentNotifierProvider)
          .recordRefund(invoiceId: invoiceId, method: method, amount: amount, note: note);
      if (!context.mounted) return;
      AppToast.success(context, message: 'Refund recorded.');
      ref.invalidate(invoiceDetailViewProvider(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: billingMessageForRpc(error));
    }
  }
}

class _InvoiceDetailScaffold extends StatelessWidget {
  const _InvoiceDetailScaffold({
    required this.view,
    required this.allowPartialPayments,
    required this.onRefresh,
    required this.onPrint,
    required this.onVoid,
    required this.onRecordPayment,
    required this.onRecordRefund,
  });

  final InvoiceDetailViewState view;
  final bool allowPartialPayments;
  final VoidCallback onRefresh;
  final VoidCallback onPrint;
  final Future<void> Function() onVoid;
  final Future<void> Function(PaymentMethod method, String amount, String? reference, String? note) onRecordPayment;
  final Future<void> Function(PaymentMethod method, String amount, String note) onRecordRefund;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final invoice = view.invoice;
    final canPay = view.canRecordPayment && !invoice.status.isVoided && !invoice.status.isTerminal;
    final showRefund = view.canRefund && invoice.payments.any((p) => !p.isRefund);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md),
            child: Row(
              children: [
                AppIconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          if (invoice.patientDisplayName != null) invoice.patientDisplayName,
                          if (invoice.branchName != null) invoice.branchName,
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                InvoiceStatusBadge(status: invoice.status),
                const SizedBox(width: SpacingTokens.sm),
                AppIconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: onRefresh),
                const SizedBox(width: SpacingTokens.xs),
                AppButton(
                  label: 'Print receipt',
                  variant: AppButtonVariant.outline,
                  expand: false,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  onPressed: onPrint,
                ),
                if (view.canVoid && invoice.status.isVoidable) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(label: 'Void', variant: AppButtonVariant.destructive, expand: false, onPressed: onVoid),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, 0, SpacingTokens.lg, SpacingTokens.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;

                  final itemsCard = AppCard(
                    title: const Text('Line items'),
                    child: Column(
                      children: [
                        for (final item in invoice.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                            child: Row(
                              children: [
                                Expanded(child: Text(item.description, style: theme.textTheme.bodyMedium)),
                                Text(
                                  BillingFormatting.formatMoney(item.lineTotal, currency: invoice.currency),
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );

                  final paymentsCard = AppCard(
                    title: const Text('Payment history'),
                    child: invoice.payments.isEmpty
                        ? Text(
                            'No payments recorded yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                          )
                        : Column(
                            children: [
                              for (final payment in invoice.payments)
                                _PaymentRow(payment: payment, currency: invoice.currency),
                            ],
                          ),
                  );

                  final sideColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InvoiceTotalsPanel(invoice: invoice),
                      if (invoice.voidReason != null) ...[
                        const SizedBox(height: SpacingTokens.md),
                        AppCard(title: const Text('Void reason'), child: Text(invoice.voidReason!)),
                      ],
                      if (canPay) ...[
                        const SizedBox(height: SpacingTokens.lg),
                        PaymentForm(
                          invoice: invoice,
                          allowPartialPayments: allowPartialPayments,
                          enabled: true,
                          onSubmit: onRecordPayment,
                        ),
                      ],
                      if (showRefund) ...[
                        const SizedBox(height: SpacingTokens.lg),
                        RefundForm(enabled: true, onSubmit: onRecordRefund),
                      ],
                    ],
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              itemsCard,
                              const SizedBox(height: SpacingTokens.lg),
                              paymentsCard,
                            ],
                          ),
                        ),
                        const SizedBox(width: SpacingTokens.lg),
                        SizedBox(width: 360, child: sideColumn),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      itemsCard,
                      const SizedBox(height: SpacingTokens.lg),
                      paymentsCard,
                      const SizedBox(height: SpacingTokens.lg),
                      sideColumn,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.currency});

  final Payment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final isRefund = payment.isRefund;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Row(
        children: [
          Icon(
            isRefund ? Icons.undo : Icons.payments_outlined,
            size: 18,
            color: isRefund ? colors.destructive : colors.primary,
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${payment.method.label}${isRefund ? ' (refund)' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  BillingFormatting.formatDateTime(payment.recordedAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          Text(
            BillingFormatting.formatMoney(payment.amount, currency: currency),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isRefund ? colors.destructive : null,
            ),
          ),
        ],
      ),
    );
  }
}
