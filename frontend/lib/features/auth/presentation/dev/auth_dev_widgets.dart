import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Local bootstrap administrator credentials (see backend seed migrations).
abstract final class AuthDevBootstrapCredentials {
  static const username = 'admin';
  static const password = 'admin';
}

/// Debug-only auth presentation widgets (permission demo, quick admin sign-in, etc.).
abstract final class AuthDevWidgets {
  const AuthDevWidgets._();

  /// Dev-only shortcuts shown beneath the login modal. Removed before production.
  static Widget panel({Key? key, required VoidCallback onLoginAsAdmin, bool isSubmitting = false}) {
    if (!kDebugMode) return const SizedBox.shrink();
    return const SizedBox.shrink();
  }
}
