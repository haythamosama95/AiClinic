import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_forgot_password_info.dart';

/// Centered auth card for staff sign-in on `/login`.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({this.forgotMode = false, super.key});

  /// When true, shows administrator-mediated password recovery copy (`?forgot=1`).
  final bool forgotMode;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  late var _showForgotPasswordInfo = widget.forgotMode;
  String? _usernameError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    if (widget.forgotMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _clearSignInErrors());
    }
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forgotMode && !oldWidget.forgotMode) {
      setState(() => _showForgotPasswordInfo = true);
      _clearSignInErrors();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearSignInErrors() {
    ref.read(authNotifierProvider.notifier).clearSignInError();
    ref.read(authSessionProvider.notifier).clearSignInFailureMessage();
  }

  void _resetSignInPresentation() {
    ref.read(authNotifierProvider.notifier).resetSignInForm();
    ref.read(authSessionProvider.notifier).clearSignInFailureMessage();
    _usernameController.clear();
    _passwordController.clear();
    setState(() {
      _showForgotPasswordInfo = false;
      _usernameError = null;
      _passwordError = null;
    });
  }

  bool _validateFields() {
    final usernameError = validateStaffUsername(_usernameController.text);
    final passwordError = _passwordController.text.isEmpty ? 'Password is required.' : null;
    setState(() {
      _usernameError = usernameError;
      _passwordError = passwordError;
    });
    return usernameError == null && passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validateFields()) {
      return;
    }
    setState(() => _showForgotPasswordInfo = false);
    await ref.read(authNotifierProvider.notifier).signIn(
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }

  void _toggleForgotPasswordInfo() {
    final willShow = !_showForgotPasswordInfo;
    if (willShow) {
      _clearSignInErrors();
    }
    setState(() => _showForgotPasswordInfo = willShow);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final sessionFailure = ref.watch(authSessionProvider.select((session) => session.failureMessage));
    final errorMessage = authState.errorMessage ?? (authState.isSubmitting ? null : sessionFailure);
    final colors = context.colors;

    ref.listen<AuthUiState>(authNotifierProvider, (previous, next) {
      if (previous?.isSubmitting == true && next.isSubmitting == false && next.errorMessage == null) {
        if (!mounted) return;
        final setupRequired = ref.read(authSessionProvider).context?.setupRequired ?? false;
        context.go(setupRequired ? AppRoutes.bootstrap : AppRoutes.home);
      }
    });

    return Scaffold(
      backgroundColor: colors.surfaceCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s6,
              vertical: AppSpacing.s8,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppCard(
                    padding: AppCardPadding.lg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Login',
                          textAlign: TextAlign.center,
                          style: context.typography.title.copyWith(color: colors.textPrimary),
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        AppFormField(
                          label: 'Username',
                          error: _usernameError,
                          child: AppTextField(
                            controller: _usernameController,
                            hintText: 'Username',
                            leadingIcon: LucideIcons.user,
                            textInputAction: TextInputAction.next,
                            disabled: authState.isSubmitting,
                            invalid: _usernameError != null,
                            autofillHints: const [AutofillHints.username],
                            onChanged: (_) {
                              if (_usernameError != null) {
                                setState(() => _usernameError = validateStaffUsername(_usernameController.text));
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        AppFormField(
                          label: 'Password',
                          error: _passwordError,
                          child: AppPasswordField(
                            controller: _passwordController,
                            hintText: '••••••••',
                            disabled: authState.isSubmitting,
                            invalid: _passwordError != null,
                            onSubmitted: authState.isSubmitting ? null : (_) => _submit(),
                            onChanged: (_) {
                              if (_passwordError != null && _passwordController.text.isNotEmpty) {
                                setState(() => _passwordError = null);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: AppButton(
                            label: 'Forgot password?',
                            variant: AppButtonVariant.ghost,
                            size: AppButtonSize.sm,
                            onPressed: _toggleForgotPasswordInfo,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        AppButton(
                          label: 'Login',
                          fullWidth: true,
                          loading: authState.isSubmitting,
                          onPressed: authState.isSubmitting ? null : _submit,
                        ),
                        if (_showForgotPasswordInfo) ...[
                          const SizedBox(height: AppSpacing.s4),
                          AppAlert(
                            variant: AppAlertVariant.info,
                            title: LoginForgotPasswordInfo.title,
                            body: LoginForgotPasswordInfo.body,
                          ),
                        ] else if (errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          AppAlert(
                            variant: AppAlertVariant.danger,
                            title: errorMessage,
                            dismissible: true,
                            onDismiss: _clearSignInErrors,
                          ),
                        ],
                      ],
                    ),
                  ),
                  AuthDevWidgets.panel(
                    isSubmitting: authState.isSubmitting,
                    onLoginAsAdmin: () {
                      ref.read(authNotifierProvider.notifier).signIn(
                            username: AuthDevBootstrapCredentials.username,
                            password: AuthDevBootstrapCredentials.password,
                          );
                    },
                  ),
                  if (context.canPop()) ...[
                    const SizedBox(height: AppSpacing.s4),
                    AppButton(
                      label: 'Close',
                      variant: AppButtonVariant.ghost,
                      onPressed: () {
                        _resetSignInPresentation();
                        context.pop();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
