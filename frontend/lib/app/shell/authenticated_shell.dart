import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/clinic_app_shell.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Authenticated route shell: production chrome, warm-up hooks, and dev overlays.
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(permissionServiceProvider).canAccessAppointments()) {
      ref.watch(appointmentQueueShellWarmProvider);
    }

    return ShellDevShellWrapper(
      child: ClinicAppShell(child: child),
    );
  }
}
