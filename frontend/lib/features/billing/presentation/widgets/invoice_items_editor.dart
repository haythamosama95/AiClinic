import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/line_discount_field.dart';

/// Editable line items table for draft invoices (V1-6 US1).
class InvoiceItemsEditor extends StatefulWidget {
  const InvoiceItemsEditor({
    required this.invoice,
    required this.canEdit,
    required this.canApplyDiscount,
    required this.activeDiscountScope,
    required this.isMutating,
    required this.onAddItem,
    required this.onUpdateItem,
    required this.onRemoveItem,
    required this.onApplyLineDiscount,
    required this.onClearLineDiscounts,
    super.key,
  });

  final InvoiceDetail invoice;
  final bool canEdit;
  final bool canApplyDiscount;
  final DiscountScope? activeDiscountScope;
  final bool isMutating;
  final Future<void> Function(String description, String quantity, String unitPrice) onAddItem;
  final Future<void> Function(String itemId, String description, String quantity, String unitPrice) onUpdateItem;
  final Future<void> Function(String itemId) onRemoveItem;
  final Future<void> Function(String itemId, DiscountKind? kind, String? value) onApplyLineDiscount;
  final Future<void> Function() onClearLineDiscounts;

  @override
  State<InvoiceItemsEditor> createState() => _InvoiceItemsEditorState();
}

class _InvoiceItemsEditorState extends State<InvoiceItemsEditor> {
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();
  String? _editingItemId;

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  void _startEdit(InvoiceItem item) {
    setState(() {
      _editingItemId = item.id;
      _descriptionController.text = item.description;
      _quantityController.text = item.quantity;
      _unitPriceController.text = item.unitPrice.wireValue;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingItemId = null;
      _descriptionController.clear();
      _quantityController.text = '1';
      _unitPriceController.clear();
    });
  }

  Future<void> _saveItem() async {
    final description = _descriptionController.text.trim();
    final quantity = _quantityController.text.trim();
    final unitPrice = _unitPriceController.text.trim();
    if (description.isEmpty) {
      return;
    }

    if (_editingItemId != null) {
      await widget.onUpdateItem(_editingItemId!, description, quantity, unitPrice);
    } else {
      await widget.onAddItem(description, quantity, unitPrice);
    }
    _cancelEdit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final currency = widget.invoice.currency;
    final items = widget.invoice.items;

    return AppCard(
      title: const Text('Line items'),
      description: Text('${items.length} item${items.length == 1 ? '' : 's'}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SpacingTokens.lg),
              child: Text(
                'No line items yet. Add services rendered during the visit.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...items.map(
              (item) => _ItemRow(
                item: item,
                currency: currency,
                canEdit: widget.canEdit,
                canApplyDiscount: widget.canApplyDiscount,
                activeScope: widget.activeDiscountScope,
                isExpanded: _editingItemId == item.id,
                onEdit: () => _startEdit(item),
                onRemove: () => widget.onRemoveItem(item.id),
                onApplyLineDiscount: (kind, value) => widget.onApplyLineDiscount(item.id, kind, value),
                onClearScope: widget.onClearLineDiscounts,
              ),
            ),
          if (widget.canEdit) ...[
            const SizedBox(height: SpacingTokens.lg),
            const Divider(),
            const SizedBox(height: SpacingTokens.md),
            Text(
              _editingItemId == null ? 'Add line item' : 'Edit line item',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: SpacingTokens.md),
            AppTextField(controller: _descriptionController, label: 'Description'),
            const SizedBox(height: SpacingTokens.sm),
            Row(
              children: [
                Expanded(
                  child: AppTextField(controller: _quantityController, label: 'Quantity'),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: AppTextField(controller: _unitPriceController, label: 'Unit price'),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
            Row(
              children: [
                AppButton(
                  label: _editingItemId == null ? 'Add item' : 'Save changes',
                  isLoading: widget.isMutating,
                  expand: false,
                  onPressed: _saveItem,
                ),
                if (_editingItemId != null) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, expand: false, onPressed: _cancelEdit),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.currency,
    required this.canEdit,
    required this.canApplyDiscount,
    required this.activeScope,
    required this.isExpanded,
    required this.onEdit,
    required this.onRemove,
    required this.onApplyLineDiscount,
    required this.onClearScope,
  });

  final InvoiceItem item;
  final String currency;
  final bool canEdit;
  final bool canApplyDiscount;
  final DiscountScope? activeScope;
  final bool isExpanded;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final Future<void> Function(DiscountKind? kind, String? value) onApplyLineDiscount;
  final Future<void> Function() onClearScope;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: isExpanded ? colors.primary : colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
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
                          item.description,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.quantity} × ${BillingFormatting.formatMoney(item.unitPrice, currency: currency)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    BillingFormatting.formatMoney(item.lineTotal, currency: currency),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: SpacingTokens.xs),
                    AppIconButton(icon: const Icon(Icons.edit_outlined, size: 18), tooltip: 'Edit', onPressed: onEdit),
                    AppIconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: colors.destructive),
                      tooltip: 'Remove',
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
              if (canApplyDiscount && canEdit) ...[
                const SizedBox(height: SpacingTokens.md),
                LineDiscountField(
                  item: item,
                  currency: currency,
                  enabled: canEdit,
                  activeScope: activeScope,
                  onApply: onApplyLineDiscount,
                  onClearScope: onClearScope,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
