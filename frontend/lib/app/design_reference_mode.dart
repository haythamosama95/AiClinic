import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Whether the app mimics the web design reference (no auth, shell-first).
///
/// Enabled in debug `flutter run` only — disabled under `flutter test` so auth
/// guard tests keep production redirect behavior.
bool get isDesignReferenceMode {
  if (!kDebugMode) {
    return false;
  }

  try {
    final bindingType = SchedulerBinding.instance.runtimeType.toString();
    return !bindingType.contains('Test');
  } catch (_) {
    // Binding not initialized (pure unit tests) — keep production auth guards.
    return false;
  }
}
