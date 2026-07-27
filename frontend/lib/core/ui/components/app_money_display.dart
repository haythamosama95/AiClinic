import 'package:flutter/material.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Formatted currency amount with optional emphasis and negative styling (web `MoneyDisplay`).
class AppMoneyDisplay extends StatelessWidget {
  const AppMoneyDisplay({
    required this.amount,
    required this.currency,
    this.emphasis = false,
    this.negative,
    super.key,
  });

  final Money amount;
  final String currency;
  final bool emphasis;
  final bool? negative;

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
    final isNegative = negative ?? amount.isNegative;
    final displayAmount = isNegative ? Money.parse(amount.wireValue.replaceFirst('-', '')) : amount;
    final formatted = MoneyFormatter.format(displayAmount, currency: currency);
    final amountColor = isNegative ? colors.statusDangerFg : colors.textPrimary;
    final amountStyle = base.copyWith(
      color: amountColor,
      fontWeight: emphasis ? FontWeight.w600 : base.fontWeight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(
        TextSpan(
          children: [
            if (isNegative) TextSpan(text: '\u2212', style: amountStyle),
            TextSpan(text: formatted, style: amountStyle),
          ],
        ),
        style: base,
      ),
    );
  }
}
