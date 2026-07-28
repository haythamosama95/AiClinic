import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';

/// Result from [VitalSignFormDialog.show].
class VitalSignFormResult {
  const VitalSignFormResult({required this.predefinedVitalSignId, required this.name, required this.value, this.unit});

  final String predefinedVitalSignId;
  final String name;
  final String value;
  final String? unit;
}

/// Dialog for recording or editing a vital sign measurement.
class VitalSignFormDialog extends StatefulWidget {
  const VitalSignFormDialog({required this.catalog, required this.usedPredefinedIds, this.editingEntry, super.key});

  final List<CatalogItem> catalog;
  final Set<String> usedPredefinedIds;
  final VisitVitalSign? editingEntry;

  static Future<VitalSignFormResult?> show(
    BuildContext context, {
    required List<CatalogItem> catalog,
    required Set<String> usedPredefinedIds,
    VisitVitalSign? editingEntry,
  }) {
    final isEditing = editingEntry != null;
    return AppDialog.show<VitalSignFormResult>(
      context,
      title: isEditing ? 'Edit vital sign' : 'Record vital sign',
      description: isEditing
          ? 'Update the measurement type or value for this entry.'
          : 'Choose the measurement type and enter the value taken during this encounter.',
      size: AppDialogSize.sm,
      child: VitalSignFormDialog(catalog: catalog, usedPredefinedIds: usedPredefinedIds, editingEntry: editingEntry),
    );
  }

  @override
  State<VitalSignFormDialog> createState() => _VitalSignFormDialogState();
}

class _VitalSignFormDialogState extends State<VitalSignFormDialog> {
  late final TextEditingController _valueController;
  late String? _selectedId;
  String? _typeError;
  String? _valueError;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.editingEntry?.value ?? '');
    _selectedId = widget.editingEntry?.predefinedVitalSignId ?? _firstAvailableId();
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  String? _firstAvailableId() {
    for (final item in widget.catalog) {
      if (!widget.usedPredefinedIds.contains(item.id)) {
        return item.id;
      }
    }
    return widget.catalog.isNotEmpty ? widget.catalog.first.id : null;
  }

  CatalogItem? _selectedCatalogItem() {
    final id = _selectedId;
    if (id == null) {
      return null;
    }
    for (final item in widget.catalog) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  String? _valuePlaceholderFor(CatalogItem? item) {
    if (item == null) {
      return null;
    }
    return switch (item.name.trim().toLowerCase()) {
      'blood pressure' => '120/80',
      'heart rate' => '72',
      'temperature' => '36.8',
      'spo2' || 'spo₂' => '98',
      'respiratory rate' => '16',
      'weight' => '68',
      'height' => '165',
      'bmi' => '24.2',
      _ => null,
    };
  }

  void _submit() {
    final selected = _selectedCatalogItem();
    final value = _valueController.text.trim();
    String? typeError;
    String? valueError;

    if (selected == null) {
      typeError = 'Select a vital sign type.';
    }
    if (value.isEmpty) {
      valueError = 'Enter the measured value.';
    }

    if (typeError != null || valueError != null) {
      setState(() {
        _typeError = typeError;
        _valueError = valueError;
      });
      return;
    }

    Navigator.of(context).pop(
      VitalSignFormResult(
        predefinedVitalSignId: selected!.id,
        name: selected.name,
        value: value,
        unit: selected.defaultUnit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCatalogItem();
    final unit = selected?.defaultUnit?.trim();
    final valueLabel = unit != null && unit.isNotEmpty ? 'Value ($unit)' : 'Value';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: 'vital-sign-type',
          label: 'Vital sign',
          requiredMark: true,
          error: _typeError,
          child: AppSelect(
            id: 'vital-sign-type-select',
            value: _selectedId,
            placeholder: 'Select type…',
            invalid: _typeError != null,
            options: [
              for (final item in widget.catalog)
                AppSelectOption(
                  value: item.id,
                  label: item.name,
                  disabled:
                      widget.usedPredefinedIds.contains(item.id) &&
                      item.id != widget.editingEntry?.predefinedVitalSignId,
                ),
            ],
            onChanged: (id) {
              setState(() {
                _selectedId = id;
                _typeError = null;
                if (id != widget.editingEntry?.predefinedVitalSignId) {
                  _valueController.clear();
                }
              });
            },
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'vital-sign-value',
          label: valueLabel,
          requiredMark: true,
          error: _valueError,
          child: AppTextInput(
            controller: _valueController,
            placeholder: _valuePlaceholderFor(selected) ?? '—',
            invalid: _valueError != null,
            onChanged: (_) {
              if (_valueError != null) {
                setState(() => _valueError = null);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              leadingIcon: const Icon(Icons.monitor_heart_outlined, size: 16),
              onPressed: _submit,
              child: Text(_isEditing ? 'Save changes' : 'Add vital sign'),
            ),
          ],
        ),
      ],
    );
  }
}
