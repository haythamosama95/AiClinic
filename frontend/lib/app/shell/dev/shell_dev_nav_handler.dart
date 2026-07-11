import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';

/// Dispatches debug-only dev nav actions (fill dummy clinic, reset clinic).
abstract final class ShellDevNavHandler {
  const ShellDevNavHandler._();

  static bool isActionItem(String itemId) => ShellDevNav.actionItemIds.contains(itemId);

  static Future<void> handleItemSelection(BuildContext context, WidgetRef ref, String itemId) async {
    switch (itemId) {
      case ShellDevFillDummyClinic.itemId:
        await ShellDevFillDummyClinic.handleNavSelection(context, ref);
      case ShellDevResetClinic.itemId:
        await ShellDevResetClinic.handleNavSelection(context, ref);
    }
  }
}
