import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/presentation/ui_pending_placeholder_page.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';

/// Full-screen host for the login modal on the `/login` route.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  var _loginPresentationGeneration = 0;

  void _clearSignInErrors() {
    ref.read(authNotifierProvider.notifier).clearSignInError();
    ref.read(authSessionProvider.notifier).clearSignInFailureMessage();
  }

  void _resetSignInPresentation() {
    ref.read(authNotifierProvider.notifier).resetSignInForm();
    ref.read(authSessionProvider.notifier).clearSignInFailureMessage();
    setState(() => _loginPresentationGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final sessionFailure = ref.watch(authSessionProvider.select((session) => session.failureMessage));
    final errorMessage = authState.errorMessage ?? (authState.isSubmitting ? null : sessionFailure);
    final colors = context.semanticColors;

    ref.listen<AuthUiState>(authNotifierProvider, (previous, next) {
      if (previous?.isSubmitting == true && next.isSubmitting == false && next.errorMessage == null) {
        if (mounted) context.go(AppRoutes.bootstrap);
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: UiPendingPlaceholderPage(featureName: 'Setup', routeName: AppRoutes.bootstrap),
          ),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoginModal(
                      key: ValueKey(_loginPresentationGeneration),
                      isSubmitting: authState.isSubmitting,
                      errorMessage: errorMessage,
                      initialShowForgotPasswordInfo: GoRouterState.of(
                        context,
                      ).uri.queryParameters.containsKey('forgot'),
                      onDismissSignInError: _clearSignInErrors,
                      onClose: () {
                        _resetSignInPresentation();
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                      onSubmit: (username, password) {
                        ref.read(authNotifierProvider.notifier).signIn(username: username, password: password);
                      },
                    ),
                    AuthDevWidgets.panel(
                      isSubmitting: authState.isSubmitting,
                      onLoginAsAdmin: () {
                        ref
                            .read(authNotifierProvider.notifier)
                            .signIn(
                              username: AuthDevBootstrapCredentials.username,
                              password: AuthDevBootstrapCredentials.password,
                            );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
