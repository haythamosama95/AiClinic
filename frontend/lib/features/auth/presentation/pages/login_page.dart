import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';

/// Full-screen host for the login modal on the `/login` route.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final colors = context.semanticColors;

    ref.listen<AuthUiState>(authNotifierProvider, (previous, next) {
      if (previous?.isSubmitting == true && next.isSubmitting == false && next.errorMessage == null) {
        if (mounted) context.go(AppRoutes.bootstrap);
      }
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
            child: LoginModal(
              isSubmitting: authState.isSubmitting,
              errorMessage: authState.errorMessage,
              onClose: () => context.canPop() ? context.pop() : context.go(AppRoutes.startupEntry),
              onForgotPassword: () => context.go(AppRoutes.forgotPassword),
              onSubmit: (username, password) {
                ref.read(authNotifierProvider.notifier).signIn(username: username, password: password);
              },
            ),
          ),
        ),
      ),
    );
  }
}
