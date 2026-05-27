import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Security-conscious logging for clinic auth and bootstrap paths.
abstract final class AppLog {
  static const String _defaultName = 'ai_clinic';

  /// Test-only sink; not used in production.
  @visibleForTesting
  static final List<({String level, String message})> debugRecords = [];

  @visibleForTesting
  static void debugClearRecords() {
    debugRecords.clear();
  }

  /// Informational events (also emitted in profile/release builds).
  static void info(String message, {String name = _defaultName}) {
    final formatted = _format(message);
    _record('info', formatted);
    developer.log(formatted, name: name, level: 800);
  }

  /// Failures and actionable diagnostics (profile/release).
  static void warning(String message, {String name = _defaultName}) {
    final formatted = _format(message);
    _record('warning', formatted);
    developer.log(formatted, name: name, level: 900);
  }

  /// Verbose diagnostics (debug builds only).
  static void fine(String message, {String name = _defaultName}) {
    if (!kDebugMode) {
      return;
    }
    final formatted = _format(message);
    _record('fine', formatted);
    developer.log(formatted, name: name, level: 500);
  }

  static const int _maxDebugRecords = 5000;

  static void _record(String level, String message) {
    if (!kDebugMode) {
      return;
    }
    debugRecords.add((level: level, message: message));
    if (debugRecords.length > _maxDebugRecords) {
      debugRecords.removeRange(0, debugRecords.length - _maxDebugRecords);
    }
  }

  static final List<RegExp> _redactionPatterns = [
    RegExp(r'password=\S+', caseSensitive: false),
    RegExp(r'password:\s*\S+', caseSensitive: false),
    RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false),
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
    // PHI patterns
    RegExp(r'p_full_name[=:]\s*\S+', caseSensitive: false),
    RegExp(r'p_phone[=:]\s*[\d+\-\s]+', caseSensitive: false),
    RegExp(r'p_date_of_birth[=:]\s*\d{4}-\d{2}-\d{2}', caseSensitive: false),
    RegExp(r'p_national_id[=:]\s*\S+', caseSensitive: false),
  ];

  /// Strips common secret patterns; never pass raw passwords, tokens, or emails.
  static String _format(String message) {
    var result = message;
    for (final pattern in _redactionPatterns) {
      result = result.replaceAll(pattern, '[redacted]');
    }
    return result;
  }
}
