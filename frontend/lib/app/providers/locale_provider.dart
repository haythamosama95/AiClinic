import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localeKey = 'aiclinic.locale';

/// Persists and exposes the active app locale for production feature screens.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    Future<void>.microtask(_load);
    return const Locale('en');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code == null) {
      return;
    }
    final loaded = Locale(code);
    if (state != loaded) {
      state = loaded;
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }
}

/// Active locale for [MaterialApp.router] and gen-l10n lookups.
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

/// Resolves text direction from the active locale (Arabic → RTL).
TextDirection textDirectionForLocale(Locale locale) {
  return locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}
