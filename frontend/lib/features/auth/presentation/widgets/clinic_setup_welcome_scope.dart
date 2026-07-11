import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/presentation/providers/clinic_setup_welcome_shown_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_dialog.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_complete_dialog.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog.dart';

/// Prevents overlapping setup-flow presentations.
bool _clinicSetupFlowRunning = false;

/// Prevents showing the completion celebration more than once per sign-in spell.
bool _clinicSetupCelebrationShown = false;

/// Presents the first-run clinic setup flow: welcome → setup dialog → completion dialog.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartSetupFlow());
  }

  Future<void> _presentCelebration() async {
    if (!mounted || _clinicSetupCelebrationShown) {
      return;
    }

    _clinicSetupCelebrationShown = true;
    final draft = ref.read(clinicSetupProvider).draft;
    await ClinicSetupCompleteDialog.show(context, draft: draft);
  }

  Future<void> _maybeStartSetupFlow() async {
    if (!mounted || _clinicSetupFlowRunning) {
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

    final staffMemberId = session.staffProfile.staffMemberId;
    final welcomeShownNotifier = ref.read(clinicSetupWelcomeShownProvider(staffMemberId).notifier);

    _clinicSetupFlowRunning = true;
    try {
      if (welcomeShownNotifier.tryMarkShown()) {
        await ClinicSetupWelcomeDialog.show(context);
      }

      if (!mounted) {
        return;
      }

      final latestAuth = ref.read(authSessionProvider);
      final latestSession = latestAuth.context;
      if (!latestAuth.isAuthenticated || latestSession == null || !latestSession.needsClinicSetup) {
        return;
      }

      final draftBeforeSetup = ref.read(clinicSetupProvider).draft;
      final completed = await ClinicSetupDialog.show(context);
      if (!mounted || !completed) {
        return;
      }

      _clinicSetupCelebrationShown = true;
      await ClinicSetupCompleteDialog.show(context, draft: draftBeforeSetup);
    } finally {
      _clinicSetupFlowRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      if (!mounted) {
        return;
      }

      if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        final staffMemberId = previous?.context?.staffProfile.staffMemberId;
        if (staffMemberId != null) {
          ref.invalidate(clinicSetupWelcomeShownProvider(staffMemberId));
        }
        _clinicSetupCelebrationShown = false;
        return;
      }

      final previousStaffMemberId = previous?.context?.staffProfile.staffMemberId;
      final nextStaffMemberId = next.context?.staffProfile.staffMemberId;
      if (previousStaffMemberId != null &&
          nextStaffMemberId != null &&
          previousStaffMemberId != nextStaffMemberId) {
        ref.invalidate(clinicSetupWelcomeShownProvider(previousStaffMemberId));
      }

      final wasLocked = previous?.context?.needsClinicSetup ?? false;
      final isLocked = next.context?.needsClinicSetup ?? false;
      if (wasLocked && !isLocked && next.isAuthenticated && !_clinicSetupCelebrationShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_presentCelebration());
          }
        });
        return;
      }

      if (_clinicSetupFlowRunning) {
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
          unawaited(_maybeStartSetupFlow());
        }
      });
    });

    return widget.child;
  }
}
