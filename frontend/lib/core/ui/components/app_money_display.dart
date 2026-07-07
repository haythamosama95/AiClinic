import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Formatted currency amount with optional emphasis and negative styling (web `MoneyDisplay`).
class AppMoneyDisplay extends StatelessWidget {
  const AppMoneyDisplay({required this.amount, this.currency = 'EGP', this.emphasis = false, this.negative, super.key});

  final double amount;
  final String currency;
  final bool emphasis;
  final bool? negative;

  static final _formatter = NumberFormat('#,##0.00', 'en_EG');

  /// Anchors on [AppTypography.body] for font family/metrics, then applies parent
  /// [DefaultTextStyle] size/weight only for compact contextual wrappers (table
  /// cells, footers, entity cards). Never adopts display/heading sizes from
  /// unrelated ancestors.
  static TextStyle _baseTextStyle(BuildContext context) {
    final body = AppTypography.body(context);
    final parent = DefaultTextStyle.of(context).style;
    final themeBody = Theme.of(context).textTheme.bodyMedium!;
    final bodyFontSize = body.fontSize ?? themeBody.fontSize!;

    final parentFontSize = parent.fontSize;
    if (parentFontSize != null && parentFontSize > bodyFontSize) {
      return body;
    }

    final parentOverridesTypography =
        parent.fontSize != themeBody.fontSize ||
        parent.fontWeight != themeBody.fontWeight ||
        parent.height != themeBody.height;

    if (!parentOverridesTypography) {
      return body;
    }

    return body.copyWith(
      fontSize: parent.fontSize,
      fontWeight: parent.fontWeight,
      height: parent.height,
      letterSpacing: parent.letterSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = _baseTextStyle(context);
    final isNegative = negative ?? amount < 0;
    final formatted = _formatter.format(amount.abs());
    final amountColor = isNegative ? colors.statusDangerFg : colors.textPrimary;
    final amountStyle = base.copyWith(
      color: amountColor,
      fontWeight: emphasis ? FontWeight.w600 : base.fontWeight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final currencyStyle = base.copyWith(color: colors.textTertiary);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(
        TextSpan(
          children: [
            if (isNegative) TextSpan(text: '\u2212', style: amountStyle),
            TextSpan(text: formatted, style: amountStyle),
            const TextSpan(text: ' '),
            TextSpan(text: currency, style: currencyStyle),
          ],
        ),
        style: base,
      ),
    );
  }
}
