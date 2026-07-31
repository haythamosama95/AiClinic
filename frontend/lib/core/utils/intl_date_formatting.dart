import 'package:intl/date_symbol_data_local.dart';

bool _initialized = false;

/// Loads locale symbol data required by [DateFormat] patterns with explicit locales.
///
/// Safe to call repeatedly. Must run before formatting with locales such as
/// `en_GB` or `ar_EG` (e.g. date pickers in the design system).
Future<void> ensureIntlDateFormattingInitialized() async {
  if (_initialized) {
    return;
  }

  await Future.wait([initializeDateFormatting('en_GB'), initializeDateFormatting('ar_EG')]);

  _initialized = true;
}
