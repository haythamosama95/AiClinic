import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_action_button.dart';

bool invoiceHasLineDiscountScope(InvoiceDetail invoice) {
  return invoice.items.any((item) => !item.lineDiscountAmount.isZero || item.lineDiscountKind != null);
}

bool invoiceHasInvoiceDiscountScope(InvoiceDetail invoice) {
  return invoice.discountKind != null || !invoice.discountAmount.isZero;
}

/// Mutually exclusive line vs invoice discount controls with RBAC gating (V1-6 US3).
class InvoiceDiscountSection extends ConsumerStatefulWidget {
  const InvoiceDiscountSection({
    required this.invoiceId,
    required this.invoice,
    required this.canApplyDiscount,
    required this.isMutating,
    super.key,
  });

  final String invoiceId;
  final InvoiceDetail invoice;
  final bool canApplyDiscount;
  final bool isMutating;

  @override
  ConsumerState<InvoiceDiscountSection> createState() => _InvoiceDiscountSectionState();
}

class _InvoiceDiscountSectionState extends ConsumerState<InvoiceDiscountSection> {
  DiscountKind _invoiceKind = DiscountKind.percentage;
  final _invoiceValueController = TextEditingController();
  final Map<String, DiscountKind> _lineKinds = {};
  final Map<String, TextEditingController> _lineValueControllers = {};

  InvoiceEditorNotifier get _notifier => ref.read(invoiceEditorProvider(widget.invoiceId).notifier);

  @override
  void dispose() {
    _invoiceValueController.dispose();
    for (final controller in _lineValueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _lineController(String itemId) {
    return _lineValueControllers.putIfAbsent(itemId, TextEditingController.new);
  }

  DiscountKind _lineKind(String itemId) => _lineKinds[itemId] ?? DiscountKind.percentage;

  Future<void> _applyInvoiceDiscount() async {
    try {
      await _notifier.applyInvoiceDiscount(
        kind: _invoiceKind,
        value: _invoiceValueController.text.trim(),
      );
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  Future<void> _clearInvoiceDiscount() async {
    try {
      await _notifier.applyInvoiceDiscount();
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  Future<void> _applyLineDiscount(InvoiceItem item) async {
    try {
      await _notifier.applyLineDiscount(
        itemId: item.id,
        kind: _lineKind(item.id),
        value: _lineController(item.id).text.trim(),
      );
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  Future<void> _clearLineDiscount(String itemId) async {
    try {
      await _notifier.applyLineDiscount(itemId: itemId);
    } on RpcFailure catch (error) {
      ref.showAppToast(message: billingMessageForRpc(error), variant: AppToastVariant.danger);
    }
  }

  Future<void> _clearAllLineDiscounts() async {
    for (final item in widget.invoice.items) {
      if (!item.lineDiscountAmount.isZero || item.lineDiscountKind != null) {
        await _clearLineDiscount(item.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canApplyDiscount) {
      return BillingActionButton(
        disabledReason: 'You do not have permission to apply discounts.',
        child: AppButton(
          label: 'Apply discount',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.secondary,
          leadingIcon: LucideIcons.percent,
          disabled: true,
          onPressed: null,
        ),
      );
    }

    final lineScopeActive = invoiceHasLineDiscountScope(widget.invoice);
    final invoiceScopeActive = invoiceHasInvoiceDiscountScope(widget.invoice);
    final lineInputsEnabled = !invoiceScopeActive && !widget.isMutating;
    final invoiceInputsEnabled = !lineScopeActive && !widget.isMutating;
    final kindOptions = DiscountKind.values
        .map((kind) => AppSelectOption(value: kind, label: kind.label))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Discounts', style: context.typography.title),
        const SizedBox(height: AppSpacing.s3),
        if (lineScopeActive && invoiceScopeActive)
          AppAlert(
            variant: AppAlertVariant.warning,
            title: 'Discount scopes are mutually exclusive.',
            body: 'Clear one scope before using the other.',
            actions: [
              AppButton(
                label: 'Clear line discounts',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: widget.isMutating ? null : _clearAllLineDiscounts,
              ),
              AppButton(
                label: 'Clear invoice discount',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: widget.isMutating ? null : _clearInvoiceDiscount,
              ),
            ],
          )
        else if (lineScopeActive)
          AppAlert(
            variant: AppAlertVariant.info,
            title: 'Line-level discounts are active.',
            body: 'Clear them before applying an invoice-level discount.',
            actions: [
              AppButton(
                label: 'Clear line discounts',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: widget.isMutating ? null : _clearAllLineDiscounts,
              ),
            ],
          )
        else if (invoiceScopeActive)
          AppAlert(
            variant: AppAlertVariant.info,
            title: 'An invoice-level discount is active.',
            body: 'Clear it before applying line-level discounts.',
            actions: [
              AppButton(
                label: 'Clear invoice discount',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: widget.isMutating ? null : _clearInvoiceDiscount,
              ),
            ],
          ),
        if (widget.invoice.items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s3),
          Text('Line-level', style: context.typography.bodyStrong),
          const SizedBox(height: AppSpacing.s2),
          for (final item in widget.invoice.items)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s3),
              child: AppCard(
                variant: AppCardVariant.flat,
                padding: AppCardPadding.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.description, style: context.typography.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpacing.s2),
                    AppSelect<DiscountKind>(
                      value: _lineKind(item.id),
                      options: kindOptions,
                      disabled: !lineInputsEnabled,
                      onChanged: lineInputsEnabled
                          ? (value) => setState(() => _lineKinds[item.id] = value)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    AppTextField(
                      controller: _lineController(item.id),
                      hintText: _lineKind(item.id) == DiscountKind.percentage ? '0–100' : 'Amount',
                      disabled: !lineInputsEnabled,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        AppButton(
                          label: 'Apply',
                          size: AppButtonSize.sm,
                          disabled: !lineInputsEnabled,
                          onPressed: lineInputsEnabled ? () => _applyLineDiscount(item) : null,
                        ),
                        if (!item.lineDiscountAmount.isZero) ...[
                          const SizedBox(width: AppSpacing.s2),
                          AppButton(
                            label: 'Clear',
                            size: AppButtonSize.sm,
                            variant: AppButtonVariant.ghost,
                            disabled: !lineInputsEnabled,
                            onPressed: lineInputsEnabled ? () => _clearLineDiscount(item.id) : null,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.s3),
        Text('Invoice total', style: context.typography.bodyStrong),
        const SizedBox(height: AppSpacing.s2),
        AppCard(
          variant: AppCardVariant.flat,
          padding: AppCardPadding.sm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSelect<DiscountKind>(
                value: _invoiceKind,
                options: kindOptions,
                disabled: !invoiceInputsEnabled,
                onChanged: invoiceInputsEnabled
                    ? (value) => setState(() => _invoiceKind = value)
                    : null,
              ),
              const SizedBox(height: AppSpacing.s2),
              AppTextField(
                controller: _invoiceValueController,
                hintText: _invoiceKind == DiscountKind.percentage ? '0–100' : 'Amount',
                disabled: !invoiceInputsEnabled,
              ),
              const SizedBox(height: AppSpacing.s2),
              Row(
                children: [
                  AppButton(
                    label: 'Apply invoice discount',
                    size: AppButtonSize.sm,
                    disabled: !invoiceInputsEnabled,
                    onPressed: invoiceInputsEnabled ? _applyInvoiceDiscount : null,
                  ),
                  if (!widget.invoice.discountAmount.isZero) ...[
                    const SizedBox(width: AppSpacing.s2),
                    AppButton(
                      label: 'Clear',
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.ghost,
                      disabled: !invoiceInputsEnabled,
                      onPressed: invoiceInputsEnabled ? _clearInvoiceDiscount : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
