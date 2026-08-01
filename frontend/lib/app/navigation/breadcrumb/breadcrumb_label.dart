import 'package:flutter/widgets.dart';

import 'package:ai_clinic/l10n/app_localizations.dart';

/// Localizable or fixed breadcrumb segment label.
sealed class BreadcrumbLabel {
  const BreadcrumbLabel();

  /// Pre-resolved display text (entity names, dynamic values).
  const factory BreadcrumbLabel.fixed(String text) = FixedBreadcrumbLabel;

  /// Resolved at render time via [AppLocalizations].
  const factory BreadcrumbLabel.l10n(String Function(AppLocalizations l10n) getter) = L10nBreadcrumbLabel;

  String resolve(BuildContext context);
}

final class FixedBreadcrumbLabel extends BreadcrumbLabel {
  const FixedBreadcrumbLabel(this.text);

  final String text;

  @override
  String resolve(BuildContext context) => text;
}

final class L10nBreadcrumbLabel extends BreadcrumbLabel {
  const L10nBreadcrumbLabel(this.getter);

  final String Function(AppLocalizations l10n) getter;

  @override
  String resolve(BuildContext context) => getter(AppLocalizations.of(context)!);
}
