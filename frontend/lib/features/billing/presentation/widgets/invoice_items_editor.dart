import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/features/billing/domain/invoice_item.dart';

typedef InvoiceItemSubmit =
    Future<bool> Function({required String description, required String quantity, required String unitPrice});

typedef InvoiceItemUpdate =
    Future<bool> Function({
      required String itemId,
      required String description,
      required String quantity,
      required String unitPrice,
    });

typedef InvoiceItemRemove = Future<bool> Function({required String itemId});

/// Draft invoice line-item editor (V1-6 US1).
class InvoiceItemsEditor extends StatefulWidget {
  const InvoiceItemsEditor({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    this.busy = false,
    this.editable = true,
  });

  final List<InvoiceItem> items;
  final InvoiceItemSubmit onAdd;
  final InvoiceItemUpdate onUpdate;
  final InvoiceItemRemove onRemove;
  final bool busy;
  final bool editable;

  @override
  State<InvoiceItemsEditor> createState() => InvoiceItemsEditorState();
}

class InvoiceItemsEditorState extends State<InvoiceItemsEditor> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();

  bool get _hasPendingAddFormData {
    final description = _descriptionController.text.trim();
    final quantity = _quantityController.text.trim();
    final unitPrice = _unitPriceController.text.trim();
    return description.isNotEmpty || unitPrice.isNotEmpty || (quantity.isNotEmpty && quantity != '1');
  }

  /// Returns an error message when issue must be blocked, or null when OK.
  String? validateBeforeIssue() {
    if (_hasPendingAddFormData) {
      final valid = _formKey.currentState?.validate() ?? false;
      if (!valid) {
        return 'Complete the line item below before issuing.';
      }
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

  Future<void> _submitNewItem() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final success = await widget.onAdd(
      description: _descriptionController.text,
      quantity: _quantityController.text.trim(),
      unitPrice: _unitPriceController.text.trim(),
    );
    if (!mounted || !success) {
      return;
    }
    _descriptionController.clear();
    _quantityController.text = '1';
    _unitPriceController.clear();
    _formKey.currentState?.reset();
  }

  static String? _validateDescription(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Description is required.';
    }
    if (trimmed.length > 500) {
      return 'Description must be 500 characters or fewer.';
    }
    return null;
  }

  static String? _validateQuantity(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Quantity is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      return 'Quantity must be greater than zero.';
    }
    return null;
  }

  static String? _validateUnitPrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Unit price is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return 'Unit price cannot be negative.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Line items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (widget.items.isEmpty)
          const Text('No items yet. Add at least one service before issuing.')
        else
          ...widget.items.map(
            (item) => _ItemRow(
              key: Key('invoice_item_${item.id}'),
              item: item,
              busy: widget.busy,
              editable: widget.editable,
              onUpdate: widget.onUpdate,
              onRemove: widget.onRemove,
            ),
          ),
        if (widget.editable) ...[
          const SizedBox(height: 16),
          Text('Add item', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('invoice_item_description'),
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  enabled: !widget.busy,
                  validator: _validateDescription,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('invoice_item_quantity'),
                        controller: _quantityController,
                        decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        enabled: !widget.busy,
                        validator: _validateQuantity,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('invoice_item_unit_price'),
                        controller: _unitPriceController,
                        decoration: const InputDecoration(labelText: 'Unit price', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        enabled: !widget.busy,
                        validator: _validateUnitPrice,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('invoice_item_add_button'),
              onPressed: widget.busy ? null : _submitNewItem,
              icon: const Icon(Icons.add),
              label: const Text('Add line item'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.busy,
    required this.editable,
    required this.onUpdate,
    required this.onRemove,
  });

  final InvoiceItem item;
  final bool busy;
  final bool editable;
  final InvoiceItemUpdate onUpdate;
  final InvoiceItemRemove onRemove;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.item.description);
    _quantityController = TextEditingController(text: widget.item.quantity);
    _unitPriceController = TextEditingController(text: widget.item.unitPrice);
  }

  @override
  void didUpdateWidget(covariant _ItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _descriptionController.text = widget.item.description;
      _quantityController.text = widget.item.quantity;
      _unitPriceController.text = widget.item.unitPrice;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.editable) ...[
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                enabled: !widget.busy,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder()),
                      enabled: !widget.busy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _unitPriceController,
                      decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder()),
                      enabled: !widget.busy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('= ${widget.item.lineTotal}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    key: Key('invoice_item_save_${widget.item.id}'),
                    onPressed: widget.busy
                        ? null
                        : () => widget.onUpdate(
                            itemId: widget.item.id,
                            description: _descriptionController.text,
                            quantity: _quantityController.text.trim(),
                            unitPrice: _unitPriceController.text.trim(),
                          ),
                    child: const Text('Save'),
                  ),
                  TextButton(
                    key: Key('invoice_item_remove_${widget.item.id}'),
                    onPressed: widget.busy ? null : () => widget.onRemove(itemId: widget.item.id),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ] else ...[
              Text(widget.item.description, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('${widget.item.quantity} × ${widget.item.unitPrice} = ${widget.item.lineTotal}'),
            ],
          ],
        ),
      ),
    );
  }
}
