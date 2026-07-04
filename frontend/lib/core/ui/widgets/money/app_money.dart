import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/foundation.dart';

/// Visual weight for read-only currency amounts.
enum AppMoneyEmphasis {
  /// Regular body weight.
  normal,

  /// Semibold weight for totals and emphasis rows.
  strong,
}

/// Read-only currency display with tabular figures and locale-aware layout.
///
/// Never use for editable amounts — use [AppMoneyField] instead.
class AppMoney extends StatelessWidget {
  /// Displays [amount] formatted with house grouping and two decimal places.
  const AppMoney({
    required Decimal amount,
    this.currency = 'EGP',
    this.locale,
    this.emphasis = AppMoneyEmphasis.normal,
    this.negative,
    this.isRefund = false,
    this.showSign = true,
    super.key,
  }) : _amount = amount;

  /// Convenience constructor for callers that still hold a [num] amount.
  factory AppMoney.fromNum(
    num amount, {
    String currency = 'EGP',
    String? locale,
    AppMoneyEmphasis emphasis = AppMoneyEmphasis.normal,
    bool? negative,
    bool isRefund = false,
    bool showSign = true,
    Key? key,
  }) {
    return AppMoney(
      amount: Decimal.parse(amount.toStringAsFixed(2)),
      currency: currency,
      locale: locale,
      emphasis: emphasis,
      negative: negative,
      isRefund: isRefund,
      showSign: showSign,
      key: key,
    );
  }

  static const _houseLocale = 'en_EG';
  static const _minusSign = '\u2212';

  final Decimal _amount;
  final String currency;
  final String? locale;
  final AppMoneyEmphasis emphasis;
  final bool? negative;
  final bool isRefund;
  final bool showSign;

  Decimal get amount => _amount;

  bool _isNegative() => negative ?? _amount < Decimal.zero;

  bool _useDangerColor() => _isNegative() || isRefund;

  String _resolveLocale(BuildContext context) =>
      locale ?? Localizations.localeOf(context).toString();

  static String _toWesternDigits(String value) {
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var result = value;
    for (var i = 0; i < 10; i++) {
      result = result
          .replaceAll(eastern[i], '$i')
          .replaceAll(persian[i], '$i');
    }
    return result;
  }

  static bool _isCurrencyLeading(String localeName, String currencyCode) {
    final sample = NumberFormat.currency(
      locale: localeName,
      name: currencyCode,
      decimalDigits: 0,
    ).format(1);
    return !RegExp(r'^\d').hasMatch(sample.trimLeft());
  }

  String _formatAmount() {
    final formatter = NumberFormat('#,##0.00', _houseLocale);
    return _toWesternDigits(formatter.format(_amount.abs().toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final resolvedLocale = _resolveLocale(context);
    final currencyFirst = _isCurrencyLeading(resolvedLocale, currency);

    final baseStyle = emphasis == AppMoneyEmphasis.strong
        ? typography.bodyStrong
        : typography.body;
    final amountStyle = typography.tabular(baseStyle).copyWith(
      color: _useDangerColor() ? colors.statusDangerFg : colors.textPrimary,
    );
    final currencyStyle = typography.tabular(typography.body).copyWith(
      color: colors.textTertiary,
    );

    final amountText = _formatAmount();
    final signText = _isNegative() && showSign ? _minusSign : '';

    final spans = <InlineSpan>[
      if (signText.isNotEmpty) TextSpan(text: signText, style: amountStyle),
      if (currencyFirst)
        TextSpan(text: '$currency ', style: currencyStyle),
      TextSpan(text: amountText, style: amountStyle),
      if (!currencyFirst)
        TextSpan(text: ' $currency', style: currencyStyle),
    ];

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(
        TextSpan(children: spans),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
