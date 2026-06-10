import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';

/// Branding accents used by the login modal illustration panel.
abstract final class _LoginModalPalette {
  static const brandCoral = Color(0xFFE8735A);
  static const panelPeach = Color(0xFFFFF3EC);
  static const forgotPasswordTan = Color(0xFFB8956A);
  static const modalRadius = 24.0;
  static const panelRadius = 16.0;
  static const compactBreakpoint = 720.0;
}

/// Administrator-mediated recovery copy (US7) — shown inline on the login form.
abstract final class LoginForgotPasswordInfo {
  static const title = 'Password recovery is administrator-mediated';
  static const subtitle =
      'AiClinic does not offer self-service password reset. Contact your clinic owner or '
      'administrator to set a new password for your staff account.\n\n'
      'If you are the clinic administrator, sign in with an owner or administrator account, open '
      'Settings → Staff, select the staff member, and use Reset password.';
}

/// Centered floating login card with branding panel and credential form.
class LoginModal extends StatefulWidget {
  const LoginModal({
    this.onClose,
    this.onDismissSignInError,
    this.onSubmit,
    this.isSubmitting = false,
    this.errorMessage,
    this.initialShowForgotPasswordInfo = false,
    super.key,
  });

  final VoidCallback? onClose;
  final VoidCallback? onDismissSignInError;
  final void Function(String username, String password)? onSubmit;
  final bool isSubmitting;
  final String? errorMessage;
  final bool initialShowForgotPasswordInfo;

  /// Presents [LoginModal] as a centered dialog over a dimmed scrim.
  static Future<void> show(
    BuildContext context, {
    void Function(String username, String password)? onSubmit,
    bool isSubmitting = false,
    String? errorMessage,
    bool initialShowForgotPasswordInfo = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
          child: LoginModal(
            onClose: () => Navigator.of(dialogContext).pop(),
            onSubmit: onSubmit,
            isSubmitting: isSubmitting,
            errorMessage: errorMessage,
            initialShowForgotPasswordInfo: initialShowForgotPasswordInfo,
          ),
        );
      },
    );
  }

  @override
  State<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends State<LoginModal> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  var _obscurePassword = true;
  late var _showForgotPasswordInfo = widget.initialShowForgotPasswordInfo;

  @override
  void initState() {
    super.initState();
    if (widget.initialShowForgotPasswordInfo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDismissSignInError?.call());
    }
  }

  @override
  void didUpdateWidget(covariant LoginModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialShowForgotPasswordInfo && !oldWidget.initialShowForgotPasswordInfo) {
      _showForgotPasswordInfo = true;
      widget.onDismissSignInError?.call();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _showForgotPasswordInfo = false);
    widget.onSubmit?.call(_usernameController.text.trim(), _passwordController.text);
  }

  void _toggleForgotPasswordInfo() {
    final willShow = !_showForgotPasswordInfo;
    if (willShow) widget.onDismissSignInError?.call();
    setState(() => _showForgotPasswordInfo = willShow);
  }

  void _resetFormFields() {
    const empty = TextEditingValue.empty;
    _usernameController.value = empty;
    _passwordController.value = empty;
    _formKey.currentState?.reset();
  }

  void _handleClose() {
    _resetFormFields();
    setState(() {
      _showForgotPasswordInfo = false;
      _obscurePassword = true;
    });
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_LoginModalPalette.modalRadius),
              boxShadow: ShadowTokens.shadowLg,
            ),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.xl),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < _LoginModalPalette.compactBreakpoint;

                  if (isCompact) {
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BrandingPanel(),
                          const SizedBox(height: SpacingTokens.xl),
                          _LoginFormSection(
                            formKey: _formKey,
                            usernameController: _usernameController,
                            passwordController: _passwordController,
                            obscurePassword: _obscurePassword,
                            isSubmitting: widget.isSubmitting,
                            errorMessage: widget.errorMessage,
                            showForgotPasswordInfo: _showForgotPasswordInfo,
                            onTogglePasswordVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                            onForgotPassword: _toggleForgotPasswordInfo,
                            onSubmit: _handleSubmit,
                          ),
                        ],
                      ),
                    );
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(flex: 45, child: _BrandingPanel()),
                        const SizedBox(width: SpacingTokens.xl),
                        Expanded(
                          flex: 55,
                          child: Center(
                            child: SingleChildScrollView(
                              child: _LoginFormSection(
                                formKey: _formKey,
                                usernameController: _usernameController,
                                passwordController: _passwordController,
                                obscurePassword: _obscurePassword,
                                isSubmitting: widget.isSubmitting,
                                errorMessage: widget.errorMessage,
                                showForgotPasswordInfo: _showForgotPasswordInfo,
                                onTogglePasswordVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                                onForgotPassword: _toggleForgotPasswordInfo,
                                onSubmit: _handleSubmit,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: SpacingTokens.sm,
            right: SpacingTokens.sm,
            child: _CloseButton(onPressed: _handleClose),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.close, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF4A4A4A),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        padding: const EdgeInsets.all(SpacingTokens.sm),
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltip: 'Close',
    );
  }
}

class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _LoginModalPalette.panelPeach,
        borderRadius: BorderRadius.circular(_LoginModalPalette.panelRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AI Clinic',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _LoginModalPalette.brandCoral,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            const AspectRatio(aspectRatio: 1.05, child: _IllustrationPlaceholder()),
          ],
        ),
      ),
    );
  }
}

class _IllustrationPlaceholder extends StatelessWidget {
  const _IllustrationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(_LoginModalPalette.panelRadius),
          border: Border.all(color: _LoginModalPalette.brandCoral.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sentiment_satisfied_alt_outlined,
                size: 48,
                color: _LoginModalPalette.brandCoral.withValues(alpha: 0.85),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Character illustration',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B5B52)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadeInOutPanel extends StatefulWidget {
  const _FadeInOutPanel({required this.visible, required this.child, super.key});

  final bool visible;
  final Widget child;

  @override
  State<_FadeInOutPanel> createState() => _FadeInOutPanelState();
}

class _FadeInOutPanelState extends State<_FadeInOutPanel> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  late final Animation<double> _opacity;

  var _showContent = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (widget.visible) {
      _showContent = true;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _FadeInOutPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      setState(() => _showContent = true);
      _controller.forward(from: 0);
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse().then((_) {
        if (mounted && !widget.visible) {
          setState(() => _showContent = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _duration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: _showContent
          ? FadeTransition(
              opacity: _opacity,
              child: IgnorePointer(
                ignoring: !widget.visible,
                child: Semantics(hidden: !widget.visible, child: widget.child),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Shared panel below the login button for sign-in errors and forgot-password info.
class _LoginStatusPanel extends StatelessWidget {
  const _LoginStatusPanel({required this.theme, required this.showForgotPasswordInfo, this.errorMessage});

  final ThemeData theme;
  final bool showForgotPasswordInfo;
  final String? errorMessage;

  bool get _visible => showForgotPasswordInfo || errorMessage != null;

  static const _panelPadding = EdgeInsets.only(top: SpacingTokens.md);

  Widget _forgotPasswordAlert() {
    return AppAlert(
      icon: Icon(Icons.info_outline, color: theme.colorScheme.primary),
      title: LoginForgotPasswordInfo.title,
      subtitle: LoginForgotPasswordInfo.subtitle,
    );
  }

  Widget _visibleContent() {
    if (showForgotPasswordInfo) return _forgotPasswordAlert();

    return AppAlert(variant: AppAlertVariant.destructive, title: errorMessage!);
  }

  @override
  Widget build(BuildContext context) {
    return _FadeInOutPanel(
      key: const ValueKey('login-status-panel'),
      visible: _visible,
      child: _visible ? Padding(padding: _panelPadding, child: _visibleContent()) : const SizedBox.shrink(),
    );
  }
}

class _LoginFormSection extends StatelessWidget {
  const _LoginFormSection({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isSubmitting,
    required this.onTogglePasswordVisibility,
    required this.onSubmit,
    required this.showForgotPasswordInfo,
    this.errorMessage,
    this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isSubmitting;
  final bool showForgotPasswordInfo;
  final String? errorMessage;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback? onForgotPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Login',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: SpacingTokens.xl),
          AppTextField(
            label: 'Username',
            controller: usernameController,
            hintText: 'Username',
            textInputAction: TextInputAction.next,
            prefixIcon: Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant),
            validator: (value) => validateStaffUsername(value ?? ''),
          ),
          const SizedBox(height: SpacingTokens.lg),
          AppTextField(
            label: 'Password',
            controller: passwordController,
            hintText: '••••••••',
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmit: isSubmitting ? null : (_) => onSubmit(),
            prefixIcon: Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
            suffixIcon: IconButton(
              onPressed: onTogglePasswordVisibility,
              icon: Icon(
                obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'This field is required';
              return null;
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: _LoginModalPalette.forgotPasswordTan,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot Password?',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: _LoginModalPalette.forgotPasswordTan,
                ),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          AppButton(label: 'Login', expand: true, isLoading: isSubmitting, onPressed: isSubmitting ? null : onSubmit),
          _LoginStatusPanel(theme: theme, showForgotPasswordInfo: showForgotPasswordInfo, errorMessage: errorMessage),
        ],
      ),
    );
  }
}
