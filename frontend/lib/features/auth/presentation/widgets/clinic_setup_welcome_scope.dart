import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_dialog.dart';

/// Presents [ClinicSetupWelcomeDialog] once per process after sign-in while setup is still required.
class ClinicSetupWelcomeScope extends ConsumerStatefulWidget {
  const ClinicSetupWelcomeScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ClinicSetupWelcomeScope> createState() => _ClinicSetupWelcomeScopeState();
}

class _ClinicSetupWelcomeScopeState extends ConsumerState<ClinicSetupWelcomeScope> {
  var _welcomeShown = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      if (_welcomeShown || !mounted) {
        return;
      }

      final wasAuthenticated = previous?.isAuthenticated ?? false;
      if (wasAuthenticated || !next.isAuthenticated) {
        return;
      }

      final session = next.context;
      if (session == null || !session.needsClinicSetup) {
        return;
      }

      _welcomeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(ClinicSetupWelcomeDialog.show(context));
      });
    });

    return widget.child;
  }
}
