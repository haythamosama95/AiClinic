import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/refund_form.dart';

/// Issued invoice detail — header, items, balance (V1-6 US1).
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String? invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = invoiceId?.trim();
    if (id == null || id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: Text('Invoice not found.')),
      );
    }

    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canViewInvoices()) {
      return const BillingAccessDeniedView(title: 'Invoice', message: 'You do not have permission to view invoices.');
    }

    if (permissions.canCreateInvoices()) {
      return _InvoiceDetailOrEditorRedirect(invoiceId: id);
    }

    return _InvoiceDetailScaffold(invoiceId: id);
  }
}

class _InvoiceDetailOrEditorRedirect extends ConsumerWidget {
  const _InvoiceDetailOrEditorRedirect({required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(invoiceDetailProvider(invoiceId));

    return detailAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: Center(child: Text(error.toString())),
      ),
      data: (detail) {
        if (detail.status == InvoiceStatus.draft) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.billingInvoiceEdit(invoiceId));
            }
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return _InvoiceDetailScaffold(invoiceId: invoiceId);
      },
    );
  }
}

class _InvoiceDetailScaffold extends ConsumerStatefulWidget {
  const _InvoiceDetailScaffold({required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<_InvoiceDetailScaffold> createState() => _InvoiceDetailScaffoldState();
}

class _InvoiceDetailScaffoldState extends ConsumerState<_InvoiceDetailScaffold> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshDetail();
      }
    });
  }

  @override
  void activate() {
    super.activate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshDetail();
      }
    });
  }

  void _refreshDetail() {
    ref.invalidate(invoiceDetailProvider(widget.invoiceId));
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(invoiceDetailProvider(widget.invoiceId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
        actions: [
          IconButton(
            key: const Key('invoice_detail_refresh_button'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDetail,
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(key: Key('invoice_detail_loading'), child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _refreshDetail, child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (detail) => _InvoiceDetailBody(invoiceId: widget.invoiceId, detail: detail),
      ),
    );
  }
}

class _InvoiceDetailBody extends StatelessWidget {
  const _InvoiceDetailBody({required this.invoiceId, required this.detail});

  final String invoiceId;
  final InvoiceDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: const Key('invoice_detail_body'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            InvoiceStatusBadge(status: detail.status),
            const SizedBox(width: 12),
            Expanded(child: Text(detail.invoiceNumber ?? 'Draft', style: theme.textTheme.titleLarge)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Patient: ${detail.patientDisplayName ?? detail.patientId}'),
        if (detail.branchName != null) Text('Branch: ${detail.branchName}'),
        const SizedBox(height: 16),
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.items.isEmpty)
          const Text('No line items.')
        else
          ...detail.items.map(
            (item) => ListTile(
              key: Key('invoice_detail_item_${item.id}'),
              title: Text(item.description),
              subtitle: Text('${item.quantity} × ${item.unitPrice}'),
              trailing: Text(item.lineTotal),
            ),
          ),
        const Divider(height: 32),
        _TotalRow(label: 'Subtotal', value: detail.subtotal),
        _TotalRow(label: 'Discount', value: detail.discountAmount),
        _TotalRow(label: 'Insurance covered', value: detail.insuranceCoveredAmount),
        _TotalRow(label: 'Balance due', value: detail.balance, emphasized: true),
        const SizedBox(height: 24),
        Text('Payments', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.payments.isEmpty)
          const Text('No payments recorded yet.', key: Key('invoice_payments_empty'))
        else
          ...detail.payments.map((payment) => _PaymentTile(payment: payment)),
        const SizedBox(height: 16),
        PaymentForm(
          key: ValueKey('payment_form_${detail.balance}_${detail.status.wireValue}'),
          invoiceId: invoiceId,
          detail: detail,
        ),
        const SizedBox(height: 16),
        RefundForm(key: ValueKey('refund_form_${detail.status.wireValue}'), invoiceId: invoiceId, detail: detail),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountLabel = payment.isRefund ? 'Refund' : 'Payment';

    return ListTile(
      key: Key('invoice_payment_${payment.id}'),
      title: Text('$amountLabel — ${payment.method.label}'),
      subtitle: Text(payment.recordedAt.toLocal().toString()),
      trailing: Text(payment.amount, style: payment.isRefund ? TextStyle(color: theme.colorScheme.error) : null),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('$value ${emphasized ? '' : ''}'.trim(), style: style),
        ],
      ),
    );
  }
}
