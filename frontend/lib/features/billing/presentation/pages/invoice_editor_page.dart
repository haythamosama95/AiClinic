import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_actions.dart';
import 'package:ai_clinic/features/billing/domain/invoice_stale_exception.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';
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
  final _discountValueController = TextEditingController();
  final _coveredAmountController = TextEditingController();
  var _issuing = false;
  var _discarding = false;
  DiscountScope _discountScope = DiscountScope.invoice;
  String? _lineItemId;
  DiscountKind _discountKind = DiscountKind.percentage;
  String? _insuranceProviderId;
  String? _branchCodeError;

  @override
  void dispose() {
    _searchController.dispose();
    _discountValueController.dispose();
    _coveredAmountController.dispose();
    super.dispose();
  }

  InvoiceActionPolicy _policy(InvoiceEditorState state) {
    final permissions = ref.read(permissionServiceProvider);
    return InvoiceActionPolicy(
      status: state.invoice.status,
      canCreate: permissions.canCreateInvoices(),
      canApplyDiscount: permissions.canApplyDiscount(),
      canVoidPermission: permissions.canVoidInvoice(),
      canRecordPaymentPermission: permissions.canRecordPayment(),
      canRefundPermission: permissions.canRefundPayment(),
    );
  }

  void _syncFormFromInvoice(InvoiceEditorState state) {
    final invoice = state.invoice;
    _insuranceProviderId ??= invoice.insuranceProviderId;
    if (_coveredAmountController.text.isEmpty && !invoice.insuranceCoveredAmount.isZero) {
      _coveredAmountController.text = invoice.insuranceCoveredAmount.wireValue;
    }
    if (invoice.discountKind != null && invoice.discountValue != null && _discountValueController.text.isEmpty) {
      _discountKind = invoice.discountKind!;
      _discountValueController.text = invoice.discountValue!;
      _discountScope = DiscountScope.invoice;
    }
    _lineItemId ??= invoice.items.isNotEmpty ? invoice.items.first.id : null;
  }

  Future<void> _handleRpcError(Object error) async {
    if (!mounted) {
      return;
    }
    if (error is InvoiceStaleException) {
      appToast(
        context,
        const AppToastInput(
          message: 'This invoice was updated elsewhere. Reloading…',
          variant: AppToastVariant.info,
        ),
      );
      ref.invalidate(invoiceEditorProvider(widget.invoiceId));
      return;
    }
    if (error is RpcFailure) {
      if (error.code == 'BRANCH_CODE_MISSING') {
        setState(() => _branchCodeError = billingMessageForRpc(error));
        return;
      }
      appToast(
        context,
        AppToastInput(message: billingMessageForRpc(error), variant: AppToastVariant.danger),
      );
      return;
    }
    appToast(
      context,
      const AppToastInput(
        message: 'Could not complete the billing action. Please try again.',
        variant: AppToastVariant.danger,
      ),
    );
  }

  Future<void> _issue() async {
    if (_issuing) {
      return;
    }
    setState(() {
      _issuing = true;
      _branchCodeError = null;
    });
    try {
      await ref.read(invoiceEditorProvider(widget.invoiceId).notifier).issue();
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(message: 'Invoice issued.', variant: AppToastVariant.success),
      );
      context.nav.pushBillingInvoiceDetail(widget.invoiceId);
    } on Object catch (error) {
      await _handleRpcError(error);
    } finally {
      if (mounted) {
        setState(() => _issuing = false);
      }
    }
  }

  Future<void> _discardDraft() async {
    if (_discarding) {
      return;
    }
    final confirmed = await AppConfirmationDialog.show(
      context,
      title: 'Discard draft invoice?',
      description: 'This permanently removes the draft. The visit can receive a new invoice later.',
      confirmLabel: 'Discard draft',
      variant: AppConfirmationDialogVariant.destructive,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _discarding = true);
    try {
      await ref.read(invoiceEditorProvider(widget.invoiceId).notifier).discardDraft();
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.billingInvoices);
    } on Object catch (error) {
      await _handleRpcError(error);
    } finally {
      if (mounted) {
        setState(() => _discarding = false);
      }
    }
  }

  Future<void> _addService(EligibleService service) async {
    try {
      await ref.read(invoiceEditorProvider(widget.invoiceId).notifier).addItemFromService(service);
    } on Object catch (error) {
      await _handleRpcError(error);
    }
  }

  Future<void> _removeItem(String itemId) async {
    try {
      await ref.read(invoiceEditorProvider(widget.invoiceId).notifier).removeItem(itemId);
    } on Object catch (error) {
      await _handleRpcError(error);
    }
  }

  Future<void> _applyDiscount(InvoiceEditorState state) async {
    final policy = _policy(state);
    if (!state.invoice.status.isDraft || !policy.canApplyDiscount) {
      return;
    }

    final activeScope = state.activeDiscountScope;
    if (_discountScope == DiscountScope.invoice && activeScope == DiscountScope.line) {
      appToast(
        context,
        const AppToastInput(
          message: 'Clear line-level discounts before applying an invoice-level discount.',
          variant: AppToastVariant.danger,
        ),
      );
      return;
    }
    if (_discountScope == DiscountScope.line && activeScope == DiscountScope.invoice) {
      appToast(
        context,
        const AppToastInput(
          message: 'Clear the invoice-level discount before applying line-level discounts.',
          variant: AppToastVariant.danger,
        ),
      );
      return;
    }

    final value = _discountValueController.text.trim();
    final kind = value.isEmpty ? null : _discountKind;
    final wireValue = value.isEmpty ? null : value;

    try {
      if (_discountScope == DiscountScope.invoice) {
        await ref
            .read(invoiceEditorProvider(widget.invoiceId).notifier)
            .applyInvoiceDiscount(kind: kind, value: wireValue);
      } else {
        final itemId = _lineItemId ?? state.invoice.items.firstOrNull?.id;
        if (itemId == null) {
          return;
        }
        await ref
            .read(invoiceEditorProvider(widget.invoiceId).notifier)
            .applyLineDiscount(itemId: itemId, kind: kind, value: wireValue);
      }
    } on Object catch (error) {
      await _handleRpcError(error);
    }
  }

  Future<void> _applyInsurance(InvoiceEditorState state) async {
    final policy = _policy(state);
    if (!policy.canEdit) {
      return;
    }

    final coveredAmount = _coveredAmountController.text.trim();
    if (coveredAmount.isEmpty) {
      return;
    }

    try {
      await ref
          .read(invoiceEditorProvider(widget.invoiceId).notifier)
          .setInsuranceCoverage(providerId: _insuranceProviderId, coveredAmount: coveredAmount);
    } on Object catch (error) {
      await _handleRpcError(error);
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
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: 'Could not load draft',
          description: error.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onPressed: () => ref.invalidate(invoiceEditorProvider(widget.invoiceId)),
          ),
        ),
      ),
      data: (state) {
        _syncFormFromInvoice(state);
        final invoice = state.invoice;
        final policy = _policy(state);
        final activeScope = state.activeDiscountScope;
        final providersAsync = ref.watch(activeInsuranceProvidersProvider);
        final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
        final netTotal = invoice.netTotal;
        final issueDisabledReason = InvoiceDetailActionTooltips.editDisabledReason(
          canCreate: policy.canCreate,
          status: invoice.status,
        );
        final canMutateItems = policy.canEdit && !state.isMutating;
        final canApplyDiscount = invoice.status.isDraft && policy.canApplyDiscount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Edit $displayNumber',
              description: 'Add services from the catalog, then issue when ready.',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InvoiceDetailTooltip(
                    message: InvoiceDetailActionTooltips.editMessage(
                      disabledReason: policy.canEdit ? null : 'You do not have permission to edit invoices.',
                    ),
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      loading: _discarding,
                      onPressed: !policy.canEdit || state.isMutating ? null : _discardDraft,
                      child: const Text('Discard draft'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  InvoiceDetailTooltip(
                    message: issueDisabledReason ?? 'Issue this invoice',
                    child: AppButton(
                      loading: _issuing || state.isMutating,
                      onPressed: invoice.items.isEmpty || _issuing || issueDisabledReason != null ? null : _issue,
                      child: const Text('Issue invoice'),
                    ),
                  ),
                ],
              ),
            ),
            if (_branchCodeError != null) ...[
              const SizedBox(height: AppSpacing.space3),
              AppAlert(variant: AppAlertVariant.danger, title: _branchCodeError!),
            ],
            const SizedBox(height: AppSpacing.space3),
            Builder(
              builder: (context) {
                final badgeStyle = statusBadgeStyle(invoice.status);
                return AppBadge(
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
                );
              },
            ),
            const SizedBox(height: AppSpacing.space5),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
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
                                  Text('Line items', style: AppTypography.bodyStrong(context)),
                                  const SizedBox(height: AppSpacing.space3),
                                  if (invoice.items.isEmpty)
                                    Text(
                                      'No services added yet. Search the catalog on the right.',
                                      style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                                    )
                                  else
                                    for (final item in invoice.items) ...[
                                      _EditorLineRow(
                                        item: item,
                                        currency: invoice.currency,
                                        onRemove: canMutateItems ? () => _removeItem(item.id) : null,
                                      ),
                                      Divider(height: 1, color: colors.borderSubtle),
                                    ],
                                  const InvoicePerforationDivider(),
                                  Row(
                                    children: [
                                      Text('Total', style: AppTypography.bodyStrong(context)),
                                      const Spacer(),
                                      Text(
                                        MoneyFormatter.format(netTotal, currency: invoice.currency),
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
                              child: SizedBox(
                                height: 360,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Add from catalog', style: AppTypography.bodyStrong(context)),
                                    const SizedBox(height: AppSpacing.space3),
                                    AppSearchInput(
                                      controller: _searchController,
                                      placeholder: 'Search services',
                                      disabled: !canMutateItems,
                                      onValueChange: (query) => _searchCatalog(invoice.branchId, query),
                                    ),
                                    const SizedBox(height: AppSpacing.space4),
                                    Expanded(
                                      child: _CatalogResults(
                                        branchId: invoice.branchId,
                                        currency: invoice.currency,
                                        onAdd: canMutateItems ? _addService : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _DiscountPanel(
                            discountScope: _discountScope,
                            discountKind: _discountKind,
                            activeScope: activeScope,
                            lineItemId: _lineItemId,
                            items: invoice.items,
                            discountController: _discountValueController,
                            enabled: canApplyDiscount && !state.isMutating,
                            onScopeChanged: (scope) => setState(() => _discountScope = scope),
                            onKindChanged: (kind) => setState(() => _discountKind = kind),
                            onLineItemChanged: (itemId) => setState(() => _lineItemId = itemId),
                            onApply: () => _applyDiscount(state),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space5),
                        Expanded(
                          child: _InsurancePanel(
                            providersAsync: providersAsync,
                            providerId: _insuranceProviderId,
                            coveredAmountController: _coveredAmountController,
                            currency: invoice.currency,
                            enabled: policy.canEdit && !state.isMutating,
                            onProviderChanged: (providerId) => setState(() => _insuranceProviderId = providerId),
                            onApply: () => _applyInsurance(state),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscountPanel extends StatelessWidget {
  const _DiscountPanel({
    required this.discountScope,
    required this.discountKind,
    required this.activeScope,
    required this.lineItemId,
    required this.items,
    required this.discountController,
    required this.enabled,
    required this.onScopeChanged,
    required this.onKindChanged,
    required this.onLineItemChanged,
    required this.onApply,
  });

  final DiscountScope discountScope;
  final DiscountKind discountKind;
  final DiscountScope? activeScope;
  final String? lineItemId;
  final List<InvoiceItem> items;
  final TextEditingController discountController;
  final bool enabled;
  final ValueChanged<DiscountScope> onScopeChanged;
  final ValueChanged<DiscountKind> onKindChanged;
  final ValueChanged<String> onLineItemChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
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
            Text('Discount', style: AppTypography.bodyStrong(context)),
            const SizedBox(height: AppSpacing.space3),
            AppRadioGroup(
              value: discountScope.name,
              disabled: !enabled,
              onChanged: (value) {
                onScopeChanged(DiscountScope.values.firstWhere((scope) => scope.name == value));
              },
              options: [
                AppRadioOption(
                  value: DiscountScope.invoice.name,
                  label: DiscountScope.invoice.label,
                  disabled: activeScope == DiscountScope.line,
                ),
                AppRadioOption(
                  value: DiscountScope.line.name,
                  label: DiscountScope.line.label,
                  disabled: activeScope == DiscountScope.invoice,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            if (discountScope == DiscountScope.line && items.isNotEmpty)
              AppFormField(
                id: 'discount-line-item',
                label: 'Line item',
                child: AppSelect(
                  value: lineItemId,
                  disabled: !enabled,
                  options: [for (final item in items) AppSelectOption(value: item.id, label: item.description)],
                  onChanged: onLineItemChanged,
                ),
              ),
            AppFormField(
              id: 'discount-kind',
              label: 'Discount type',
              child: AppSelect(
                value: discountKind.wireValue,
                disabled: !enabled,
                options: [
                  AppSelectOption(value: DiscountKind.percentage.wireValue, label: DiscountKind.percentage.label),
                  AppSelectOption(value: DiscountKind.fixed.wireValue, label: DiscountKind.fixed.label),
                ],
                onChanged: (value) {
                  final kind = DiscountKind.tryParse(value);
                  if (kind != null) {
                    onKindChanged(kind);
                  }
                },
              ),
            ),
            AppFormField(
              id: 'discount-value',
              label: 'Discount value',
              child: AppTextInput(
                controller: discountController,
                placeholder: discountKind == DiscountKind.percentage ? '10' : '0.00',
                disabled: !enabled,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(variant: AppButtonVariant.secondary, onPressed: enabled ? onApply : null, child: const Text('Apply discount')),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsurancePanel extends StatelessWidget {
  const _InsurancePanel({
    required this.providersAsync,
    required this.providerId,
    required this.coveredAmountController,
    required this.currency,
    required this.enabled,
    required this.onProviderChanged,
    required this.onApply,
  });

  final AsyncValue<List<InsuranceProvider>> providersAsync;
  final String? providerId;
  final TextEditingController coveredAmountController;
  final String currency;
  final bool enabled;
  final ValueChanged<String> onProviderChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
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
            Text('Insurance coverage', style: AppTypography.bodyStrong(context)),
            const SizedBox(height: AppSpacing.space3),
            providersAsync.when(
              loading: () => const AppSkeleton(height: 40),
              error: (error, _) => Text('Could not load providers: $error'),
              data: (providers) {
                if (providers.isEmpty) {
                  return Text(
                    'No active insurance providers configured for this organization.',
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  );
                }
                return AppFormField(
                  id: 'insurance-provider',
                  label: 'Insurance provider',
                  child: AppSelect(
                    value: providerId,
                    disabled: !enabled,
                    options: [
                      for (final provider in providers)
                        AppSelectOption(value: provider.id, label: provider.name),
                    ],
                    onChanged: onProviderChanged,
                  ),
                );
              },
            ),
            AppFormField(
              id: 'insurance-covered-amount',
              label: 'Covered amount',
              child: AppTextInput(
                controller: coveredAmountController,
                placeholder: '0.00',
                disabled: !enabled,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: enabled ? onApply : null,
                child: const Text('Save coverage'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorLineRow extends StatelessWidget {
  const _EditorLineRow({required this.item, required this.currency, this.onRemove});

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
                  'Qty ${item.quantity} · ${MoneyFormatter.format(item.unitPrice, currency: currency)} each',
                  style: AppTypography.caption(context).copyWith(color: context.appColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            MoneyFormatter.format(item.lineTotal, currency: currency),
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
  const _CatalogResults({required this.branchId, required this.currency, this.onAdd});

  final String branchId;
  final String currency;
  final ValueChanged<EligibleService>? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(serviceSelectorProvider(branchId));
    final colors = context.appColors;

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Text(
        error.toString(),
        style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
      ),
      data: (services) {
        if (services.isEmpty) {
          return Text(
            'No eligible services',
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
          );
        }

        return ListView.separated(
          itemCount: services.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
          itemBuilder: (context, index) {
            final service = services[index];
            return Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(MoneyFormatter.format(service.unitPrice, currency: currency)),
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

BadgeColor _badgeColor(InvoiceStatusBadgeVariant variant) {
  return switch (variant) {
    InvoiceStatusBadgeVariant.muted => BadgeColor.neutral,
    InvoiceStatusBadgeVariant.primary => BadgeColor.teal,
    InvoiceStatusBadgeVariant.accent => BadgeColor.warning,
    InvoiceStatusBadgeVariant.success => BadgeColor.success,
    InvoiceStatusBadgeVariant.destructive => BadgeColor.danger,
  };
}
