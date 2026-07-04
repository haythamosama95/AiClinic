import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

/// Draft invoice line-item editor with catalog search (V1-6 US1).
class InvoiceItemsEditor extends ConsumerStatefulWidget {
  const InvoiceItemsEditor({
    required this.invoiceId,
    required this.branchId,
    required this.currency,
    required this.items,
    required this.isMutating,
    super.key,
  });

  final String invoiceId;
  final String branchId;
  final String currency;
  final List<InvoiceItem> items;
  final bool isMutating;

  @override
  ConsumerState<InvoiceItemsEditor> createState() => InvoiceItemsEditorState();
}

class InvoiceItemsEditorState extends ConsumerState<InvoiceItemsEditor> {
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();
  EligibleService? _selectedService;

  bool get hasPendingAddFormData {
    final description = _descriptionController.text.trim();
    final quantity = _quantityController.text.trim();
    final unitPrice = _unitPriceController.text.trim();
    return description.isNotEmpty || unitPrice.isNotEmpty || (quantity.isNotEmpty && quantity != '1');
  }

  /// Returns an error message when issue must be blocked, or null when OK.
  String? validateBeforeIssue() {
    if (hasPendingAddFormData) {
      return 'Add the line item before issuing, or clear the form.';
    }
    if (widget.items.isEmpty) {
      return 'Add at least one line item before issuing.';
    }
    return null;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  InvoiceEditorNotifier get _notifier => ref.read(invoiceEditorProvider(widget.invoiceId).notifier);

  Future<void> _addManualItem() async {
    final description = _descriptionController.text.trim();
    final quantity = _quantityController.text.trim();
    final unitPrice = _unitPriceController.text.trim();
    if (description.isEmpty || quantity.isEmpty || unitPrice.isEmpty) {
      ref.showAppToast(
        message: 'Description, quantity, and unit price are required.',
        variant: AppToastVariant.danger,
      );
      return;
    }

    await _notifier.addItem(description: description, quantity: quantity, unitPrice: unitPrice);
    _descriptionController.clear();
    _quantityController.text = '1';
    _unitPriceController.clear();
    setState(() => _selectedService = null);
  }

  Future<void> _addServiceItem(EligibleService service) async {
    await _notifier.addItemFromService(service);
    setState(() => _selectedService = null);
  }

  Future<List<AppAutocompleteOption<EligibleService>>> _searchServices(String query) async {
    final results = await ref.read(serviceCatalogRepositoryProvider).searchEligibleServices(
      branchId: widget.branchId,
      query: query,
    );
    return [
      for (final service in results)
        AppAutocompleteOption(
          value: service,
          label: service.name,
          meta: '${service.unitPrice.wireValue} ${widget.currency}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Line items', style: typography.title),
        const SizedBox(height: AppSpacing.s3),
        if (widget.items.isEmpty)
          const AppEmptyState(
            variant: AppEmptyStateVariant.firstRun,
            title: 'No items yet',
            description: 'Add at least one service before issuing.',
          )
        else
          AppCard(
            variant: AppCardVariant.flat,
            padding: AppCardPadding.sm,
            child: Column(
              children: [
                for (final item in widget.items) ...[
                  _InvoiceItemRow(
                    item: item,
                    currency: widget.currency,
                    isMutating: widget.isMutating,
                    onUpdate: (description, quantity, unitPrice) => _notifier.updateItem(
                      itemId: item.id,
                      description: description,
                      quantity: quantity,
                      unitPrice: unitPrice,
                    ),
                    onRemove: () => _notifier.removeItem(item.id),
                  ),
                  if (item != widget.items.last)
                    Divider(height: 1, color: context.colors.borderSubtle),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s4),
        Text('Add from catalog', style: typography.bodyStrong),
        const SizedBox(height: AppSpacing.s2),
        AppAutocomplete<EligibleService>(
          placeholder: 'Search services…',
          disabled: widget.isMutating,
          value: _selectedService == null
              ? null
              : AppAutocompleteOption(value: _selectedService!, label: _selectedService!.name),
          onSearch: _searchServices,
          onSelected: (option) {
            if (option == null) {
              return;
            }
            setState(() => _selectedService = option.value);
            _addServiceItem(option.value);
          },
        ),
        const SizedBox(height: AppSpacing.s4),
        Text('Add custom item', style: typography.bodyStrong),
        const SizedBox(height: AppSpacing.s2),
        AppFormField(
          label: 'Description',
          child: AppTextField(
            controller: _descriptionController,
            hintText: 'Service or product description',
            disabled: widget.isMutating,
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        Row(
          children: [
            Expanded(
              child: AppFormField(
                label: 'Quantity',
                child: AppTextField(
                  controller: _quantityController,
                  hintText: '1',
                  disabled: widget.isMutating,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: AppFormField(
                label: 'Unit price',
                child: AppMoneyField(
                  currency: widget.currency,
                  disabled: widget.isMutating,
                  onValueChange: (value) {
                    _unitPriceController.text = value?.toStringAsFixed(2) ?? '';
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Add line item',
            size: AppButtonSize.sm,
            leadingIcon: LucideIcons.plus,
            loading: widget.isMutating,
            onPressed: widget.isMutating ? null : _addManualItem,
          ),
        ),
      ],
    );
  }
}

class _InvoiceItemRow extends StatefulWidget {
  const _InvoiceItemRow({
    required this.item,
    required this.currency,
    required this.isMutating,
    required this.onUpdate,
    required this.onRemove,
  });

  final InvoiceItem item;
  final String currency;
  final bool isMutating;
  final Future<void> Function(String description, String quantity, String unitPrice) onUpdate;
  final Future<void> Function() onRemove;

  @override
  State<_InvoiceItemRow> createState() => _InvoiceItemRowState();
}

class _InvoiceItemRowState extends State<_InvoiceItemRow> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.item.description);
    _quantityController = TextEditingController(text: widget.item.quantity);
  }

  @override
  void didUpdateWidget(covariant _InvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _descriptionController.text = widget.item.description;
      _quantityController.text = widget.item.quantity;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.description,
                      style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.item.quantity} × ${widget.item.unitPrice.wireValue}',
                      style: typography.tabular(typography.bodySm).copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!widget.item.lineDiscountAmount.isZero)
                      Text(
                        'Line discount: ${widget.item.lineDiscountAmount.wireValue}',
                        style: typography.bodySm.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              AppMoney(
                amount: Decimal.parse(widget.item.lineTotal.wireValue),
                currency: widget.currency,
                emphasis: AppMoneyEmphasis.strong,
              ),
              const SizedBox(width: AppSpacing.s2),
              AppIconButton(
                icon: LucideIcons.trash2,
                semanticLabel: 'Remove line item',
                disabled: widget.isMutating,
                onPressed: widget.isMutating ? null : widget.onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
