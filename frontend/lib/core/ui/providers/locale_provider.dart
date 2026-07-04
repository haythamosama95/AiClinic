import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported showcase locales — mirrors web DirectionProvider.
enum AppLocale { en, ar }

extension AppLocaleX on AppLocale {
  Locale get flutterLocale => Locale(name);
  TextDirection get textDirection =>
      this == AppLocale.ar ? TextDirection.rtl : TextDirection.ltr;
}

/// In-memory locale/direction state for the design system showcase.
class AppLocaleState {
  const AppLocaleState({required this.locale});

  final AppLocale locale;

  Locale get flutterLocale => locale.flutterLocale;
  TextDirection get textDirection => locale.textDirection;

  AppLocaleState copyWith({AppLocale? locale}) =>
      AppLocaleState(locale: locale ?? this.locale);
}

class AppLocaleNotifier extends Notifier<AppLocaleState> {
  @override
  AppLocaleState build() => const AppLocaleState(locale: AppLocale.en);

  void setLocale(AppLocale locale) {
    state = state.copyWith(locale: locale);
  }

  void toggleLocale() {
    setLocale(state.locale == AppLocale.en ? AppLocale.ar : AppLocale.en);
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleNotifier, AppLocaleState>(
  AppLocaleNotifier.new,
);
