import 'package:ai_clinic/core/money/money.dart';

/// Shared invoice balance copy and settled predicates (V1-6).
abstract final class InvoiceLabels {
  static String balanceLabel({required bool isVoided}) =>
      isVoided ? 'Balance at void' : 'Balance due';

  static bool showsSettledStyling({
    required Money balance,
    required bool isVoided,
  }) =>
      !isVoided && !balance.isPositive;
}
