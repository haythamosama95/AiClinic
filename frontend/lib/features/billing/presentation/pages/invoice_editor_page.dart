import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/discount_scope_guard.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/insurance_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_items_editor.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';

/// Draft invoice editor — items and issue (V1-6 US1).
class InvoiceEditorPage extends ConsumerWidget {
  const InvoiceEditorPage({super.key, required this.invoiceId});

  final String? invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = invoiceId?.trim();
    if (id == null || id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice editor')),
        body: const Center(child: Text('Invoice not found.')),
      );
    }

    final canCreate = ref.watch(permissionServiceProvider).canCreateInvoices();
    if (!canCreate) {
      return const BillingAccessDeniedView(
        title: 'Invoice editor',
        message: 'You do not have permission to create or edit invoices.',
      );
    }

    final editorAsync = ref.watch(invoiceEditorProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft invoice'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: editorAsync.when(
        loading: () => const Center(key: Key('invoice_editor_loading'), child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => ref.invalidate(invoiceEditorProvider(id)), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (state) => _InvoiceEditorBody(invoiceId: id, state: state),
      ),
    );
  }
}

class _InvoiceEditorBody extends ConsumerStatefulWidget {
  const _InvoiceEditorBody({required this.invoiceId, required this.state});

  final String invoiceId;
  final InvoiceEditorState state;

  @override
  ConsumerState<_InvoiceEditorBody> createState() => _InvoiceEditorBodyState();
}

class _InvoiceEditorBodyState extends ConsumerState<_InvoiceEditorBody> {
  final _itemsEditorKey = GlobalKey<InvoiceItemsEditorState>();

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final detail = state.detail;
    final notifier = ref.read(invoiceEditorProvider(widget.invoiceId).notifier);
    final canApplyDiscount = ref.watch(permissionServiceProvider).canApplyDiscount();
    final theme = Theme.of(context);
    final subtotal = double.tryParse(detail.subtotal) ?? 0;
    final invoiceDiscount = double.tryParse(detail.discountAmount) ?? 0;
    final insuranceCovered = double.tryParse(detail.insuranceCoveredAmount) ?? 0;
    final netTotal = (subtotal - invoiceDiscount).toStringAsFixed(2);
    final patientDue = (subtotal - invoiceDiscount - insuranceCovered).toStringAsFixed(2);

    return ListView(
      key: const Key('invoice_editor_body'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            InvoiceStatusBadge(status: detail.status),
            const SizedBox(width: 12),
            Expanded(child: Text(detail.patientDisplayName ?? 'Patient', style: theme.textTheme.titleLarge)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Subtotal: ${detail.subtotal} ${detail.currency}'),
        if (invoiceDiscount > 0) Text('Invoice discount: ${detail.discountAmount} ${detail.currency}'),
        Text('Net total: $netTotal ${detail.currency}', style: theme.textTheme.titleMedium),
        if (insuranceCovered > 0) Text('Patient due: $patientDue ${detail.currency}'),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          MaterialBanner(
            key: const Key('invoice_editor_error_banner'),
            content: Text(state.errorMessage!),
            actions: [TextButton(onPressed: () => notifier.reload(), child: const Text('Reload'))],
          ),
        ],
        const SizedBox(height: 24),
        InvoiceItemsEditor(
          key: _itemsEditorKey,
          items: detail.items,
          busy: state.isBusy,
          onAdd: notifier.addItem,
          onUpdate: notifier.updateItem,
          onRemove: notifier.removeItem,
        ),
        const SizedBox(height: 24),
        DiscountScopeGuard(
          detail: detail,
          canApplyDiscount: canApplyDiscount,
          busy: state.isBusy,
          onApplyLineDiscount: notifier.applyLineDiscount,
          onClearLineDiscount: ({required itemId}) => notifier.clearLineDiscount(itemId: itemId),
          onApplyInvoiceDiscount: notifier.applyInvoiceDiscount,
          onClearInvoiceDiscount: notifier.clearInvoiceDiscount,
          onClearAllLineDiscounts: notifier.clearAllLineDiscounts,
        ),
        const SizedBox(height: 24),
        InsurancePanel(
          detail: detail,
          enabled: true,
          busy: state.isBusy,
          onApply: notifier.setInsuranceCoverage,
          onClear: notifier.clearInsuranceCoverage,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('invoice_draft_print_button'),
            onPressed: state.isBusy ? null : () => ReceiptPrintPreview.printInvoice(detail),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Preview receipt'),
          ),
        ),
        const SizedBox(height: 24),
        if (state.issueErrorMessage != null) ...[
          MaterialBanner(
            key: const Key('invoice_issue_error_banner'),
            content: Text(state.issueErrorMessage!),
            actions: [TextButton(onPressed: () {}, child: const Text('Dismiss'))],
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          key: const Key('invoice_issue_button'),
          onPressed: state.isBusy
              ? null
              : () async {
                  final validationError = _itemsEditorKey.currentState?.validateBeforeIssue();
                  if (validationError != null) {
                    notifier.setIssueValidationError(validationError);
                    return;
                  }

                  final invoiceNumber = await notifier.issue();
                  if (!context.mounted || invoiceNumber == null) {
                    return;
                  }
                  context.go(AppRoutes.billingInvoiceDetail(widget.invoiceId));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Invoice issued as $invoiceNumber')));
                },
          icon: state.isBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.receipt_long_outlined),
          label: Text(state.isBusy ? 'Issuing…' : 'Issue invoice'),
        ),
      ],
    );
  }
}
