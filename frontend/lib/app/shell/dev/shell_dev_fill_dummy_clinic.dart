import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

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
      '9 AM–9 PM, eight staff members, 16 fully populated patients per branch, and appointments for the past '
      'two days, today, and the next five days (including visits with SOAP notes and treatment plans where applicable). '
      'Your current session stays signed in.';

  static Future<void> handleNavSelection(BuildContext context, WidgetRef ref) async {
    if (!isEnabled) {
      return;
    }

    await confirmAndRun(context, ref);
  }

  /// Shows the confirmation dialog and runs the full dummy clinic seed (debug builds only).
  static Future<void> confirmAndRun(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    if (!isEnabled) {
      return;
    }

    await AppDialog.showConfirmation(
      context: context,
      title: confirmationTitle,
      message: confirmationMessage,
      confirmLabel: 'Fill dummy data',
      cancelLabel: 'Cancel',
      onConfirm: () => unawaited(_run(context, ref, onSuccess: onSuccess)),
    );
  }

  static Future<void> _run(BuildContext context, WidgetRef ref, {VoidCallback? onSuccess}) async {
    final ok = await ref.read(devClinicSeedProvider.notifier).fillDummyClinic();
    if (!context.mounted) {
      return;
    }

    if (ok) {
      AppToast.success(context, message: 'Dummy clinic data created.');
      onSuccess?.call();
      return;
    }

    final errorMessage = ref.read(devClinicSeedProvider).errorMessage;
    if (errorMessage != null) {
      AppToast.error(context, message: errorMessage);
    }
  }
}
