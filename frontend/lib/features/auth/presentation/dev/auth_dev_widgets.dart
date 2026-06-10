import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug-only auth presentation widgets (permission demo, quick admin sign-in, etc.).
///
/// Widgets in this library must only be rendered behind [kDebugMode] or via
/// conditional imports so they are excluded from release builds.
abstract final class AuthDevWidgets {
  const AuthDevWidgets._();

  /// Returns an empty placeholder until dev widgets are reintroduced.
  static Widget panel({Key? key}) {
    if (!kDebugMode) return const SizedBox.shrink();
    return const SizedBox.shrink();
  }
}
