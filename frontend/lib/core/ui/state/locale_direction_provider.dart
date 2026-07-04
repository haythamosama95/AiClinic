import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/core/logging/app_log.dart';

const _localeStorageKey = 'aiclinic-locale';

/// Persisted UI locale and its derived layout direction.
///
/// [TextDirection] is derived from [locale] (`ar` → RTL). [MaterialApp.locale]
/// drives ambient direction automatically — no manual [Directionality] wrap is
/// required at the app root.
@immutable
class LocaleDirectionState {
  const LocaleDirectionState({required this.locale});

  final Locale locale;

  /// Layout direction implied by [locale].
  TextDirection get textDirection =>
      locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  static const supportedLocales = [Locale('en'), Locale('ar')];
}

class LocaleDirectionNotifier extends Notifier<LocaleDirectionState> {
  @override
  LocaleDirectionState build() {
    Future.microtask(_loadPersistedLocale);
    return const LocaleDirectionState(locale: Locale('en'));
  }

  /// Sets the active locale and persists the choice.
  Future<void> setLocale(Locale locale) async {
    final normalized = _normalizeLocale(locale);
    if (state.locale == normalized) {
      return;
    }
    state = LocaleDirectionState(locale: normalized);
    await _persistLocale(normalized);
  }

  /// Toggles between English and Arabic.
  Future<void> toggleLocale() {
    final next = state.locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
    return setLocale(next);
  }

  Future<void> _loadPersistedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_localeStorageKey);
      if (stored == null) {
        return;
      }
      final locale = _localeFromWire(stored);
      if (locale == null || locale == state.locale) {
        return;
      }
      state = LocaleDirectionState(locale: locale);
    } on Exception catch (error) {
      AppLog.warning('ui.locale.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> _persistLocale(Locale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeStorageKey, locale.languageCode);
    } on Exception catch (error) {
      AppLog.warning('ui.locale.save_failed reason=${error.runtimeType}');
    }
  }

  Locale _normalizeLocale(Locale locale) {
    return switch (locale.languageCode) {
      'ar' => const Locale('ar'),
      _ => const Locale('en'),
    };
  }

  Locale? _localeFromWire(String value) => switch (value) {
    'ar' => const Locale('ar'),
    'en' => const Locale('en'),
    _ => null,
  };
}

/// Global locale preference; feeds [MaterialApp.locale].
final localeDirectionProvider =
    NotifierProvider<LocaleDirectionNotifier, LocaleDirectionState>(
      LocaleDirectionNotifier.new,
    );
