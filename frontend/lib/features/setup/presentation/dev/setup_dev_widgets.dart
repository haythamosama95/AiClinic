import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug-only setup wizard shortcuts (dummy fill, reset installation).
abstract final class SetupDevWidgets {
  const SetupDevWidgets._();

  static Widget panel({
    Key? key,
    required VoidCallback onFillDummy,
    required VoidCallback onResetInstallation,
    bool isBusy = false,
  }) {
    if (!kDebugMode) return const SizedBox.shrink();
    return const SizedBox.shrink();
  }
}
