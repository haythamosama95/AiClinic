import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/service_catalog/application/promotion_validation.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';

/// Promotion price + inclusive date window editor for one branch row (US4).
class PromotionEditor extends StatefulWidget {
  const PromotionEditor({
    super.key,
    required this.effectivePrice,
    required this.onSave,
    required this.onClear,
    this.initialPromotion,
    this.isSaving = false,
  });

  final String effectivePrice;
  final ServicePromotion? initialPromotion;
  final bool isSaving;
  final Future<void> Function({required String price, required DateTime startDate, required DateTime endDate}) onSave;
  final Future<void> Function() onClear;

  @override
  State<PromotionEditor> createState() => PromotionEditorState();
}

class PromotionEditorState extends State<PromotionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceController;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPromotion;
    _priceController = TextEditingController(text: initial?.wirePrice ?? '');
    _startDate = initial?.startDate;
    _endDate = initial?.endDate;
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  bool get _hasPromotion => widget.initialPromotion != null;

  bool get _isExpired {
    final promotion = widget.initialPromotion;
    if (promotion == null) {
      return false;
    }
    return promotion.isExpiredOn(DateTime.now());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) {
      return;
    }
    await widget.onSave(price: _priceController.text.trim(), startDate: start, endDate: end);
  }

  Future<void> _clear() async {
    await widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Promotion', style: theme.textTheme.titleSmall),
              if (_hasPromotion && _isExpired) ...[
                const SizedBox(width: SpacingTokens.sm),
                AppBadge(label: 'Expired', variant: AppBadgeVariant.accent),
              ],
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTextField(
            label: 'Promotion price',
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !widget.isSaving,
            description: 'Must not exceed effective price (${widget.effectivePrice}).',
            validator: (value) {
              final priceError = PromotionValidation.validatePrice(value);
              if (priceError != null) {
                return priceError;
              }
              return PromotionValidation.validateAgainstEffective(
                promotionPrice: value ?? '',
                effectivePrice: widget.effectivePrice,
              );
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppDateField(
            label: 'Start date',
            value: _startDate,
            enabled: !widget.isSaving,
            onChanged: (value) => setState(() => _startDate = value),
            validator: (_) => PromotionValidation.validateDateRange(start: _startDate, end: _endDate),
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppDateField(
            label: 'End date',
            value: _endDate,
            enabled: !widget.isSaving,
            onChanged: (value) => setState(() => _endDate = value),
            validator: (_) => PromotionValidation.validateDateRange(start: _startDate, end: _endDate),
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            children: [
              AppButton(
                label: _hasPromotion ? 'Update promotion' : 'Set promotion',
                onPressed: widget.isSaving ? null : _submit,
                isLoading: widget.isSaving,
              ),
              if (_hasPromotion) ...[
                const SizedBox(width: SpacingTokens.sm),
                AppButton(
                  label: 'Clear promotion',
                  variant: AppButtonVariant.secondary,
                  onPressed: widget.isSaving ? null : _clear,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
