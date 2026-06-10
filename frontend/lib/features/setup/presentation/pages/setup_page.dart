import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/app/shell/widgets/shell_content_placeholder.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/first_sign_in_warning_dialog.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';

/// Full-screen host for the clinic setup wizard on the `/bootstrap` route.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPasswordWarning());
  }

  void _maybeShowPasswordWarning() {
    final auth = ref.read(authSessionProvider).context;
    final setup = ref.read(setupNotifierProvider);
    if (auth == null || !auth.staffProfile.isBootstrapAdmin || setup.hasShownPasswordWarning) {
      return;
    }

    FirstSignInWarningDialog.show(
      context,
      onContinue: () => ref.read(setupNotifierProvider.notifier).markPasswordWarningShown(),
    );
  }

  void _goHome() {
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _fillDummy() async {
    final ok = await ref.read(setupNotifierProvider.notifier).finishSetupWithDummyData();
    if (ok && mounted) {
      ref.read(setupNotifierProvider.notifier).markSetupComplete();
    }
  }

  Future<void> _resetInstallation() async {
    await ref.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    ref.listen<SetupUiState>(setupNotifierProvider, (previous, next) {
      if (next.step == SetupWizardStep.complete && previous?.step != SetupWizardStep.complete) {
        _goHome();
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: AuthenticatedShell(child: ShellContentPlaceholder())),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: ColoredBox(color: colors.background.withValues(alpha: 0.35)),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
                child: SetupModal(
                  onFinished: _goHome,
                  onFillDummy: _fillDummy,
                  onResetInstallation: _resetInstallation,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
