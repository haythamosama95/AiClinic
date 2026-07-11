import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_dialog.dart';

/// Tracks whether the welcome dialog was shown for the current signed-in spell.
///
/// Shared across [ClinicSetupWelcomeScope] instances (login backdrop + routed shell).
bool _clinicSetupWelcomeShown = false;

/// Presents [ClinicSetupWelcomeDialog] once after each sign-in while setup is still required.
class ClinicSetupWelcomeScope extends ConsumerStatefulWidget {
  const ClinicSetupWelcomeScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ClinicSetupWelcomeScope> createState() => _ClinicSetupWelcomeScopeState();
}

class _ClinicSetupWelcomeScopeState extends ConsumerState<ClinicSetupWelcomeScope> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePresentWelcome());
  }

  void _maybePresentWelcome() {
    if (!mounted || _clinicSetupWelcomeShown) {
      return;
    }

    final auth = ref.read(authSessionProvider);
    if (!auth.isAuthenticated) {
      return;
    }

    final session = auth.context;
    if (session == null || !session.needsClinicSetup) {
      return;
    }

    _presentWelcome();
  }

  void _presentWelcome() {
    if (_clinicSetupWelcomeShown || !mounted) {
      return;
    }

    _clinicSetupWelcomeShown = true;
    unawaited(ClinicSetupWelcomeDialog.show(context));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      if (!mounted) {
        return;
      }

      if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        _clinicSetupWelcomeShown = false;
        return;
      }

      if (_clinicSetupWelcomeShown) {
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _presentWelcome();
        }
      });
    });

    return widget.child;
  }
}
