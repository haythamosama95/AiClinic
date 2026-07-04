import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/service_catalog/application/promotion_validation.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';

/// Promotion price and inclusive date window for one branch row (015 US4).
class PromotionEditor extends StatefulWidget {
  const PromotionEditor({
    required this.effectivePriceWire,
    required this.disabled,
    required this.onSave,
    required this.onClear,
    this.promotion,
    this.submitted = false,
    super.key,
  });

  final ServicePromotion? promotion;
  final String effectivePriceWire;
  final bool disabled;
  final bool submitted;

  /// Persists a complete promotion; caller performs RPC in edit mode.
  final ValueChanged<ServicePromotion> onSave;

  /// Clears the promotion; caller performs RPC in edit mode.
  final VoidCallback onClear;

  @override
  State<PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends State<PromotionEditor> {
  Decimal? _price;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _priceError;
  String? _dateError;
  String? _invariantError;

  @override
  void initState() {
    super.initState();
    _syncFromPromotion(widget.promotion);
  }

  @override
  void didUpdateWidget(covariant PromotionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.promotion != widget.promotion) {
      _syncFromPromotion(widget.promotion);
    }
  }

  void _syncFromPromotion(ServicePromotion? promotion) {
    _price = promotion == null ? null : Decimal.parse(promotion.wirePrice);
    _startDate = promotion?.startDate;
    _endDate = promotion?.endDate;
  }

  bool get _hasPromotion => widget.promotion != null;

  bool get _isExpired {
    final promotion = widget.promotion;
    if (promotion == null) {
      return false;
    }
    return promotion.isExpiredOn(DateTime.now());
  }

  void _validateFields() {
    final priceWire = _price == null ? '' : Money.parse(_price!.toStringAsFixed(2)).wireValue;
    setState(() {
      _priceError = PromotionValidation.validatePrice(priceWire);
      _dateError = PromotionValidation.validateDateRange(start: _startDate, end: _endDate);
      _invariantError = PromotionValidation.validateAgainstEffective(
        promotionPrice: priceWire,
        effectivePrice: widget.effectivePriceWire,
      );
    });
  }

  static String _formatWireDate(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void _handleSave() {
    _validateFields();
    if (_priceError != null || _dateError != null || _invariantError != null) {
      return;
    }
    final priceWire = Money.parse(_price!.toStringAsFixed(2)).wireValue;
    final promotion = ServicePromotion.tryParse(
      price: priceWire,
      startDate: _formatWireDate(_startDate!),
      endDate: _formatWireDate(_endDate!),
    );
    if (promotion == null) {
      return;
    }
    widget.onSave(promotion);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final showErrors = widget.submitted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Promotion',
                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ),
            if (_hasPromotion && _isExpired)
              AppBadge(
                color: AppBadgeColor.neutral,
                child: Text('Expired', style: typography.caption),
              ),
            if (_hasPromotion && !_isExpired)
              AppBadge(
                color: AppBadgeColor.warning,
                child: Text('Active', style: typography.caption),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Promotion price',
          requiredMark: true,
          error: showErrors ? _priceError : null,
          child: AppMoneyField(
            value: _price,
            disabled: widget.disabled,
            invalid: showErrors && _priceError != null,
            hintText: '0.00',
            onValueChange: (value) => setState(() {
              _price = value;
              if (showErrors) {
                _priceError = null;
                _invariantError = null;
              }
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Start date',
          requiredMark: true,
          error: showErrors ? _dateError : null,
          child: AppDatePicker(
            value: _startDate,
            disabled: widget.disabled,
            invalid: showErrors && _dateError != null,
            onChanged: (value) => setState(() {
              _startDate = value;
              if (showErrors) {
                _dateError = null;
              }
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'End date',
          requiredMark: true,
          helperText: 'Promotion window is inclusive on both dates.',
          error: showErrors ? _dateError : null,
          child: AppDatePicker(
            value: _endDate,
            disabled: widget.disabled,
            invalid: showErrors && _dateError != null,
            onChanged: (value) => setState(() {
              _endDate = value;
              if (showErrors) {
                _dateError = null;
              }
            }),
          ),
        ),
        if (showErrors && _invariantError != null) ...[
          const SizedBox(height: AppSpacing.s2),
          Text(
            _invariantError!,
            style: typography.caption.copyWith(color: colors.statusDangerFg),
          ),
        ],
        const SizedBox(height: AppSpacing.s3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_hasPromotion)
              AppButton(
                label: 'Clear promotion',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                disabled: widget.disabled,
                onPressed: widget.disabled ? null : widget.onClear,
              ),
            if (_hasPromotion) const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: _hasPromotion ? 'Update promotion' : 'Set promotion',
              size: AppButtonSize.sm,
              disabled: widget.disabled,
              onPressed: widget.disabled ? null : _handleSave,
            ),
          ],
        ),
        if (_hasPromotion) ...[
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Current: ${BillingFormatting.formatMoney(widget.promotion!.price)} · '
            '${BillingFormatting.formatDate(widget.promotion!.startDate)} – '
            '${BillingFormatting.formatDate(widget.promotion!.endDate)}',
            style: typography.caption.copyWith(color: colors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
