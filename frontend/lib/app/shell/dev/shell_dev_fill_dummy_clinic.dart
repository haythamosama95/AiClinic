import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';

/// Dev Options nav item and handlers for filling dummy clinic data.
abstract final class ShellDevFillDummyClinic {
  const ShellDevFillDummyClinic._();

  static const itemId = 'fill-dummy-clinic';
  static const label = 'Fill Dummy Clinic';
  static const icon = Icons.auto_fix_high_outlined;

  static bool get isEnabled => kDebugMode;

  static const confirmationTitle = 'Fill dummy clinic data?';
  static const confirmationMessage =
      'This completely wipes the server first — organization, branches, staff (except your bootstrap login), '
      'patients, appointments, visits, billing, and shifts — then creates one organization, three branches open daily '
      '9 AM–9 PM, eight staff members, doctor shifts for today and the next five days, 16 fully populated patients per branch, '
      'and appointments for the past two days, today, and the next five days (including visits with clinical notes and treatment '
      'plans where applicable). '
      'Your current session stays signed in.';

  static Future<void> handleNavSelection(BuildContext context, WidgetRef ref) async {
    if (!isEnabled) {
      return;
    }

    await confirmAndRun(context, ref);
  }

  static Future<bool> confirm(BuildContext context) async {
    if (!isEnabled) {
      return false;
    }

    return AppConfirmationDialog.show(
      context,
      title: confirmationTitle,
      description: confirmationMessage,
      confirmLabel: 'Fill dummy data',
      cancelLabel: 'Cancel',
    );
  }

  /// Shows the confirmation dialog and runs the full dummy clinic seed (debug builds only).
  static Future<void> confirmAndRun(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    final confirmed = await confirm(context);
    if (confirmed && context.mounted) {
      await run(context, ref, onSuccess: onSuccess);
    }
  }

  static Future<void> run(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    final ok = await ref.read(devClinicSeedProvider.notifier).fillDummyClinic();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dummy clinic data created.')));
      onSuccess?.call();
      return;
    }

    final errorMessage = ref.read(devClinicSeedProvider).errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }
}
