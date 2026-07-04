import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/discount_scope_guard.dart';

/// Per-line discount input for draft invoices (V1-6 US3).
class LineDiscountField extends StatefulWidget {
  const LineDiscountField({
    required this.item,
    required this.currency,
    required this.enabled,
    required this.activeScope,
    required this.onApply,
    required this.onClearScope,
    super.key,
  });

  final InvoiceItem item;
  final String currency;
  final bool enabled;
  final DiscountScope? activeScope;
  final Future<void> Function(DiscountKind? kind, String? value) onApply;
  final Future<void> Function() onClearScope;

  @override
  State<LineDiscountField> createState() => _LineDiscountFieldState();
}

class _LineDiscountFieldState extends State<LineDiscountField> {
  DiscountKind _kind = DiscountKind.percentage;
  final _valueController = TextEditingController();
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncFromItem();
  }

  @override
  void didUpdateWidget(LineDiscountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.lineDiscountKind != widget.item.lineDiscountKind) {
      _syncFromItem();
    }
  }

  void _syncFromItem() {
    _kind = widget.item.lineDiscountKind ?? DiscountKind.percentage;
    _valueController.text = widget.item.lineDiscountValue ?? '';
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  bool get _blocked => widget.activeScope == DiscountScope.invoice;

  Future<void> _apply() async {
    setState(() => _isSaving = true);
    try {
      final value = _valueController.text.trim();
      await widget.onApply(value.isEmpty ? null : _kind, value.isEmpty ? null : value);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _isSaving = true);
    try {
      await widget.onApply(null, null);
      _valueController.clear();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeBlocked = _blocked && widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiscountScopeGuard(
          activeScope: widget.activeScope,
          blockedScope: DiscountScope.line,
          onClearActiveScope: scopeBlocked ? () => widget.onClearScope() : null,
        ),
        if (scopeBlocked) const SizedBox(height: SpacingTokens.sm),
        Opacity(
          opacity: scopeBlocked || !widget.enabled ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: scopeBlocked || !widget.enabled,
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: AppSelectTileGroup<DiscountKind>(
                    mode: AppSelectGroupMode.radio,
                    options: [for (final kind in DiscountKind.values) AppSelectOption(value: kind, label: kind.label)],
                    values: {_kind},
                    onChanged: (values) {
                      if (values.isNotEmpty) {
                        setState(() => _kind = values.first);
                      }
                    },
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: AppTextField(
                    controller: _valueController,
                    label: 'Discount value',
                    hintText: _kind == DiscountKind.percentage ? '0–100' : 'Amount',
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                if (!widget.item.lineDiscountAmount.isZero)
                  Padding(
                    padding: const EdgeInsets.only(top: SpacingTokens.lg),
                    child: Text(
                      '-${BillingFormatting.formatMoney(widget.item.lineDiscountAmount, currency: widget.currency)}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                const SizedBox(width: SpacingTokens.sm),
                AppButton(label: 'Apply', expand: false, isLoading: _isSaving, onPressed: _apply),
                if (!widget.item.lineDiscountAmount.isZero) ...[
                  const SizedBox(width: SpacingTokens.xs),
                  AppButton(label: 'Clear', variant: AppButtonVariant.ghost, expand: false, onPressed: _clear),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
