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
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/insurance_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_discount_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_items_editor.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';

/// Draft invoice editor: items, discounts, insurance, issue (V1-6 US1/US3/US4).
class InvoiceEditorPage extends ConsumerWidget {
  const InvoiceEditorPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceDetail(auth)) {
      return const Scaffold(body: Center(child: Text('You do not have permission to edit invoices.')));
    }

    final editorAsync = ref.watch(invoiceEditorProvider(invoiceId));
    final permissions = ref.watch(permissionServiceProvider);

    return editorAsync.when(
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
                onPressed: () => ref.invalidate(invoiceEditorProvider(invoiceId)),
              ),
            ],
          ),
        ),
      ),
      data: (state) {
        final invoice = state.invoice;
        if (!invoice.status.isDraft) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.billingInvoiceDetail(invoiceId));
            }
          });
          return const Scaffold(body: Center(child: AppCircularProgress()));
        }

        return _InvoiceEditorScaffold(
          invoiceId: invoiceId,
          state: state,
          canApplyDiscount: permissions.canApplyDiscount(),
          canCreate: permissions.canCreateInvoices(),
          onIssue: () => _issue(context, ref),
          onDiscard: () => _discard(context, ref),
          onPreview: () => ReceiptPrintPreview.show(context, invoice),
          onClearLineDiscounts: () => _clearLineDiscounts(ref, state),
          onClearInvoiceDiscount: () => ref.read(invoiceEditorProvider(invoiceId).notifier).applyInvoiceDiscount(),
        );
      },
    );
  }

  Future<void> _issue(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(invoiceEditorProvider(invoiceId).notifier).issue();
      if (!context.mounted) return;
      AppToast.success(context, message: 'Invoice issued.');
      context.go(AppRoutes.billingInvoiceDetail(invoiceId));
    } on InvoiceStaleException {
      if (!context.mounted) return;
      await _showStaleDialog(context, ref);
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: billingMessageForRpc(error));
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: error.toString());
    }
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    await AppDialog.showConfirmation(
      context: context,
      title: 'Discard draft',
      message: 'This removes the draft invoice. The visit can be invoiced again.',
      confirmLabel: 'Discard',
      destructive: true,
      onConfirm: () async {
        try {
          await ref.read(invoiceEditorProvider(invoiceId).notifier).discardDraft();
          if (!context.mounted) return;
          AppToast.success(context, message: 'Draft discarded.');
          context.pop();
        } on RpcFailure catch (error) {
          if (!context.mounted) return;
          AppToast.error(context, message: billingMessageForRpc(error));
        }
      },
    );
  }

  Future<void> _clearLineDiscounts(WidgetRef ref, InvoiceEditorState state) async {
    final notifier = ref.read(invoiceEditorProvider(invoiceId).notifier);
    for (final item in state.invoice.items) {
      if (!item.lineDiscountAmount.isZero) {
        await notifier.applyLineDiscount(itemId: item.id);
      }
    }
  }

  Future<void> _showStaleDialog(BuildContext context, WidgetRef ref) async {
    await AppDialog.show(
      context: context,
      title: 'Invoice updated elsewhere',
      body: const Text('Another user changed this invoice. Reload to continue editing.'),
      actionsBuilder: (dialogContext) => [
        AppButton(
          label: 'Reload',
          expand: false,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            ref.invalidate(invoiceEditorProvider(invoiceId));
          },
        ),
      ],
    );
  }
}

class _InvoiceEditorScaffold extends ConsumerWidget {
  const _InvoiceEditorScaffold({
    required this.invoiceId,
    required this.state,
    required this.canApplyDiscount,
    required this.canCreate,
    required this.onIssue,
    required this.onDiscard,
    required this.onPreview,
    required this.onClearLineDiscounts,
    required this.onClearInvoiceDiscount,
  });

  final String invoiceId;
  final InvoiceEditorState state;
  final bool canApplyDiscount;
  final bool canCreate;
  final VoidCallback onIssue;
  final VoidCallback onDiscard;
  final VoidCallback onPreview;
  final Future<void> Function() onClearLineDiscounts;
  final Future<void> Function() onClearInvoiceDiscount;

  Future<void> _handleMutation(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
    } on InvoiceStaleException {
      if (!context.mounted) return;
      AppToast.error(context, message: 'Invoice was updated elsewhere. Reloading…');
      ref.invalidate(invoiceEditorProvider(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: billingMessageForRpc(error));
    }
  }

  Future<void> _handleCatalogMutation(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
    } on InvoiceStaleException {
      if (!context.mounted) return;
      AppToast.error(context, message: 'Invoice was updated elsewhere. Reloading…');
      ref.invalidate(invoiceEditorProvider(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, message: serviceCatalogMessageForRpc(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final invoice = state.invoice;
    final notifier = ref.read(invoiceEditorProvider(invoiceId).notifier);

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
                      Text('Edit invoice', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        invoice.patientDisplayName ?? 'Patient',
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                InvoiceStatusBadge(status: InvoiceStatus.draft),
                const SizedBox(width: SpacingTokens.sm),
                AppButton(
                  label: 'Preview receipt',
                  variant: AppButtonVariant.outline,
                  expand: false,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  onPressed: onPreview,
                ),
                if (canCreate) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(
                    label: 'Discard draft',
                    variant: AppButtonVariant.ghost,
                    expand: false,
                    isLoading: state.isMutating,
                    onPressed: onDiscard,
                  ),
                ],
                const SizedBox(width: SpacingTokens.sm),
                AppButton(label: 'Issue invoice', expand: false, isLoading: state.isMutating, onPressed: onIssue),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, 0, SpacingTokens.lg, SpacingTokens.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;
                  final mainColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InvoiceItemsEditor(
                        invoice: invoice,
                        canEdit: canCreate,
                        canApplyDiscount: canApplyDiscount,
                        activeDiscountScope: state.activeDiscountScope,
                        isMutating: state.isMutating,
                        onAddItemFromService: (service) =>
                            _handleCatalogMutation(context, ref, () => notifier.addItemFromService(service)),
                        onUpdateItemQuantity: (id, quantity) => _handleMutation(
                          context,
                          ref,
                          () => notifier.updateItemQuantity(itemId: id, quantity: quantity),
                        ),
                        onRemoveItem: (id) => _handleMutation(context, ref, () => notifier.removeItem(id)),
                        onApplyLineDiscount: (id, kind, value) => _handleMutation(
                          context,
                          ref,
                          () => notifier.applyLineDiscount(itemId: id, kind: kind, value: value),
                        ),
                        onClearLineDiscounts: () => _handleMutation(context, ref, onClearLineDiscounts),
                      ),
                      if (canApplyDiscount) ...[
                        const SizedBox(height: SpacingTokens.lg),
                        InvoiceDiscountPanel(
                          invoice: invoice,
                          enabled: canCreate,
                          activeScope: state.activeDiscountScope,
                          onApply: (kind, value) => _handleMutation(
                            context,
                            ref,
                            () => notifier.applyInvoiceDiscount(kind: kind, value: value),
                          ),
                          onClearScope: () => _handleMutation(context, ref, onClearInvoiceDiscount),
                        ),
                      ],
                      const SizedBox(height: SpacingTokens.lg),
                      InsurancePanel(
                        invoice: invoice,
                        enabled: canCreate,
                        onSave: (providerId, amount) => _handleMutation(
                          context,
                          ref,
                          () => notifier.setInsuranceCoverage(providerId: providerId, coveredAmount: amount),
                        ),
                      ),
                    ],
                  );

                  final totalsPanel = InvoiceTotalsPanel(invoice: invoice);

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: mainColumn),
                        const SizedBox(width: SpacingTokens.lg),
                        SizedBox(width: 320, child: totalsPanel),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      mainColumn,
                      const SizedBox(height: SpacingTokens.lg),
                      totalsPanel,
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
