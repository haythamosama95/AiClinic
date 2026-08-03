import 'package:flutter/widgets.dart';

import 'package:ai_clinic/l10n/app_localizations.dart';

/// Convenient access to [AppLocalizations] from any widget [BuildContext].
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
