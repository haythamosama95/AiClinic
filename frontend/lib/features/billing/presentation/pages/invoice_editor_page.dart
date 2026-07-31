import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';

/// Draft invoice editor (`/billing/invoices/:id/edit`).
class InvoiceEditorPage extends ConsumerStatefulWidget {
  const InvoiceEditorPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  ConsumerState<InvoiceEditorPage> createState() => _InvoiceEditorPageState();
}

class _InvoiceEditorPageState extends ConsumerState<InvoiceEditorPage> {
  final _searchController = TextEditingController();
  var _issuing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _issue() async {
    if (_issuing) {
      return;
    }
    setState(() => _issuing = true);
    try {
      await ref.read(invoiceEditorProvider(widget.invoiceId).notifier).issue();
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'Invoice issued.',
          variant: AppToastVariant.success,
        ),
      );
      context.nav.pushBillingInvoiceDetail(widget.invoiceId);
    } on InvoiceStaleException {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: 'This invoice was updated elsewhere. Reloading…',
            variant: AppToastVariant.info,
          ),
        );
        ref.invalidate(invoiceEditorProvider(widget.invoiceId));
      }
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: billingMessageForRpc(error),
            variant: AppToastVariant.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not issue the invoice. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _issuing = false);
      }
    }
  }

  Future<void> _addService(EligibleService service) async {
    try {
      await ref
          .read(invoiceEditorProvider(widget.invoiceId).notifier)
          .addItemFromService(service);
    } on InvoiceStaleException {
      if (mounted) {
        ref.invalidate(invoiceEditorProvider(widget.invoiceId));
      }
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: billingMessageForRpc(error),
            variant: AppToastVariant.danger,
          ),
        );
      }
    }
  }

  Future<void> _removeItem(String itemId) async {
    try {
      await ref
          .read(invoiceEditorProvider(widget.invoiceId).notifier)
          .removeItem(itemId);
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: billingMessageForRpc(error),
            variant: AppToastVariant.danger,
          ),
        );
      }
    }
  }

  void _searchCatalog(String branchId, String query) {
    ref.read(serviceSelectorProvider(branchId).notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final editorAsync = ref.watch(invoiceEditorProvider(widget.invoiceId));
    final colors = context.appColors;

    return editorAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: 'Could not load draft',
          description: error.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onPressed: () =>
                ref.invalidate(invoiceEditorProvider(widget.invoiceId)),
          ),
        ),
      ),
      data: (state) {
        final invoice = state.invoice;
        final displayNumber = BillingFormatting.invoiceDisplayNumber(
          invoice.invoiceNumber,
          invoice.id,
        );
        final netTotal = invoice.subtotal - invoice.discountAmount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Edit $displayNumber',
              description:
                  'Add services from the catalog, then issue when ready.',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  AppButton(
                    loading: _issuing || state.isMutating,
                    onPressed: invoice.items.isEmpty || _issuing
                        ? null
                        : _issue,
                    child: const Text('Issue invoice'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            InvoiceStatusBadge(status: invoice.status),
            const SizedBox(height: AppSpacing.space5),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceDefault,
                        borderRadius: BorderRadius.circular(AppRadius.x2l),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.space5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Line items',
                              style: AppTypography.bodyStrong(context),
                            ),
                            const SizedBox(height: AppSpacing.space3),
                            if (invoice.items.isEmpty)
                              Text(
                                'No services added yet. Search the catalog on the right.',
                                style: AppTypography.bodySm(
                                  context,
                                ).copyWith(color: colors.textSecondary),
                              )
                            else
                              Expanded(
                                child: ListView.separated(
                                  itemCount: invoice.items.length,
                                  separatorBuilder: (_, _) => Divider(
                                    height: 1,
                                    color: colors.borderSubtle,
                                  ),
                                  itemBuilder: (context, index) =>
                                      _EditorLineRow(
                                        item: invoice.items[index],
                                        currency: invoice.currency,
                                        onRemove: state.isMutating
                                            ? null
                                            : () => _removeItem(
                                                invoice.items[index].id,
                                              ),
                                      ),
                                ),
                              ),
                            const InvoicePerforationDivider(),
                            Row(
                              children: [
                                Text(
                                  'Total',
                                  style: AppTypography.bodyStrong(context),
                                ),
                                const Spacer(),
                                Text(
                                  BillingFormatting.formatMoney(
                                    netTotal,
                                    currency: invoice.currency,
                                  ),
                                  style: AppTypography.bodyStrong(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space5),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceSunken.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppRadius.x2l),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.space5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Add from catalog',
                              style: AppTypography.bodyStrong(context),
                            ),
                            const SizedBox(height: AppSpacing.space3),
                            AppSearchInput(
                              controller: _searchController,
                              placeholder: 'Search services',
                              onValueChange: (query) =>
                                  _searchCatalog(invoice.branchId, query),
                            ),
                            const SizedBox(height: AppSpacing.space4),
                            Expanded(
                              child: _CatalogResults(
                                branchId: invoice.branchId,
                                currency: invoice.currency,
                                onAdd: state.isMutating ? null : _addService,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EditorLineRow extends StatelessWidget {
  const _EditorLineRow({
    required this.item,
    required this.currency,
    this.onRemove,
  });

  final InvoiceItem item;
  final String currency;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description, style: AppTypography.body(context)),
                Text(
                  'Qty ${item.quantity} · ${BillingFormatting.formatMoney(item.unitPrice, currency: currency)} each',
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: context.appColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            BillingFormatting.formatMoney(item.lineTotal, currency: currency),
            style: AppTypography.bodyStrong(context),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.space2),
            AppIconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              label: 'Remove line',
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogResults extends ConsumerWidget {
  const _CatalogResults({
    required this.branchId,
    required this.currency,
    this.onAdd,
  });

  final String branchId;
  final String currency;
  final ValueChanged<EligibleService>? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(serviceSelectorProvider(branchId));
    final colors = context.appColors;

    return catalog.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Text(
        error.toString(),
        style: AppTypography.bodySm(
          context,
        ).copyWith(color: colors.textSecondary),
      ),
      data: (services) {
        if (services.isEmpty) {
          return Text(
            'No eligible services',
            style: AppTypography.bodySm(
              context,
            ).copyWith(color: colors.textSecondary),
          );
        }

        return ListView.separated(
          itemCount: services.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.borderSubtle),
          itemBuilder: (context, index) {
            final service = services[index];
            return Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(
                  BillingFormatting.formatMoney(
                    service.unitPrice,
                    currency: currency,
                  ),
                ),
                trailing: AppButton(
                  size: AppButtonSize.sm,
                  onPressed: onAdd == null ? null : () => onAdd!(service),
                  child: const Text('Add'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
