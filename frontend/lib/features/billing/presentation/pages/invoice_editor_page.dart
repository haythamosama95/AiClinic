import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/insurance_coverage_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_discount_section.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_items_editor.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Draft invoice editor — line items, discounts, insurance, and issue (V1-6 US1).
class InvoiceEditorPage extends ConsumerStatefulWidget {
  const InvoiceEditorPage({
    required this.invoiceId,
    super.key,
  });

  final String invoiceId;

  @override
  ConsumerState<InvoiceEditorPage> createState() => _InvoiceEditorPageState();
}

class _InvoiceEditorPageState extends ConsumerState<InvoiceEditorPage> {
  final _itemsEditorKey = GlobalKey<InvoiceItemsEditorState>();
  var _isIssuing = false;
  String? _summaryError;
  String? _staleEditError;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceDetail(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Invoice editor',
        description: 'You do not have permission to edit invoices.',
      );
    }

    final id = widget.invoiceId.trim();
    if (id.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Invoice not found',
        description: 'A valid invoice id is required.',
      );
    }

    if (!ref.watch(permissionServiceProvider).canCreateInvoices()) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Invoice editor',
        description: 'You do not have permission to create or edit invoices.',
      );
    }

    final editorAsync = ref.watch(invoiceEditorProvider(id));

    return editorAsync.when(
      loading: () => const RecordDetailPattern(
        title: 'Draft invoice',
        body: Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Draft invoice',
        body: AppErrorState(
          message: error is RpcFailure ? billingMessageForRpc(error) : error.toString(),
          onRetry: () => ref.invalidate(invoiceEditorProvider(id)),
        ),
      ),
      data: (state) {
        if (state.invoice.status != InvoiceStatus.draft) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.billingInvoiceDetail(id));
            }
          });
          return const RecordDetailPattern(
            title: 'Invoice',
            body: Center(child: AppSpinner()),
          );
        }
        return _buildEditor(context, id, state);
      },
    );
  }

  Future<void> _issueInvoice(String invoiceId, InvoiceEditorState state) async {
    final validationError = _itemsEditorKey.currentState?.validateBeforeIssue();
    if (validationError != null) {
      setState(() => _summaryError = validationError);
      return;
    }

    setState(() {
      _isIssuing = true;
      _summaryError = null;
      _staleEditError = null;
    });

    try {
      final invoiceNumber = await ref.read(invoiceEditorProvider(invoiceId).notifier).issue();
      if (!mounted) {
        return;
      }
      ref.showAppToast(message: 'Invoice issued as $invoiceNumber.', variant: AppToastVariant.success);
      context.go(AppRoutes.billingInvoiceDetail(invoiceId));
    } on InvoiceStaleException {
      setState(() {
        _isIssuing = false;
        _staleEditError = 'This invoice was updated elsewhere. Reload and try again.';
      });
    } on RpcFailure catch (error) {
      setState(() {
        _isIssuing = false;
        _summaryError = billingMessageForRpc(error);
      });
    } catch (_) {
      setState(() {
        _isIssuing = false;
        _summaryError = 'Unable to issue invoice. Try again.';
      });
    }
  }

  Widget _buildEditor(BuildContext context, String invoiceId, InvoiceEditorState state) {
    final invoice = state.invoice;
    final orgName = ref.watch(clinicSetupOrganizationProvider).maybeWhen(data: (org) => org?.name, orElse: () => null);
    final canApplyDiscount = ref.watch(permissionServiceProvider).canApplyDiscount();
    final isBusy = state.isMutating || _isIssuing;

    return EditorFormPattern(
      title: 'Draft invoice',
      description: invoice.patientDisplayName ?? invoice.patientId,
      headerActions: InvoiceStatusBadge(status: invoice.status),
      summaryAlert: _summaryError == null
          ? null
          : AppAlert(variant: AppAlertVariant.danger, title: _summaryError!),
      staleEditAlert: _staleEditError == null
          ? null
          : AppAlert(
              variant: AppAlertVariant.warning,
              title: _staleEditError!,
              actions: [
                AppButton(
                  label: 'Reload',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.ghost,
                  onPressed: () {
                    ref.invalidate(invoiceEditorProvider(invoiceId));
                    setState(() => _staleEditError = null);
                  },
                ),
              ],
            ),
      sections: [
        EditorFormSection(
          title: 'Items',
          fields: [
            InvoiceItemsEditor(
              key: _itemsEditorKey,
              invoiceId: invoiceId,
              branchId: invoice.branchId,
              currency: invoice.currency,
              items: invoice.items,
              isMutating: isBusy,
            ),
          ],
        ),
        EditorFormSection(
          title: 'Adjustments',
          fields: [
            InvoiceDiscountSection(
              invoiceId: invoiceId,
              invoice: invoice,
              canApplyDiscount: canApplyDiscount,
              isMutating: isBusy,
            ),
            const SizedBox(height: AppSpacing.s4),
            InsuranceCoveragePanel(
              invoiceId: invoiceId,
              invoice: invoice,
              isMutating: isBusy,
            ),
          ],
        ),
        EditorFormSection(
          title: 'Totals',
          fields: [InvoiceTotalsPanel(invoice: invoice, emphasizeBalance: false)],
        ),
      ],
      leadingContent: ReceiptPrintActions(detail: invoice, organizationName: orgName),
      footer: Row(
        children: [
          AppButton(
            label: 'Discard draft',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            disabled: isBusy,
            onPressed: isBusy
                ? null
                : () async {
                    try {
                      await ref.read(invoiceEditorProvider(invoiceId).notifier).discardDraft();
                      if (!context.mounted) return;
                      ref.showAppToast(message: 'Draft discarded.', variant: AppToastVariant.success);
                      context.nav.goBillingInvoices();
                    } on RpcFailure catch (error) {
                      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
                    }
                  },
          ),
          const Spacer(),
          AppButton(
            key: const Key('invoice_issue_button'),
            label: _isIssuing ? 'Issuing…' : 'Issue invoice',
            leadingIcon: LucideIcons.receipt,
            loading: _isIssuing,
            disabled: isBusy,
            onPressed: isBusy ? null : () => _issueInvoice(invoiceId, state),
          ),
        ],
      ),
    );
  }
}
