import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog_content.dart';

/// Legacy routed setup page. First-run setup is presented as a dialog via [ClinicSetupWelcomeScope].
class SetupPage extends ConsumerWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final wasLocked = previous?.context?.needsClinicSetup ?? false;
      final isLocked = next.context?.needsClinicSetup ?? false;
      if (!wasLocked || isLocked || !next.isAuthenticated) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        context.go(AppRoutes.home);
      });
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        const body = ClinicSetupDialogContent();
        if (constraints.hasBoundedHeight) {
          return const SingleChildScrollView(child: body);
        }
        return body;
      },
    );
  }
}
