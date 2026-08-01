import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/core/ui/components/app_brand_mark.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_password_input.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/login_query_params.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_static_backdrop.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';

const _lgBreakpoint = 960.0;

@immutable
class _Testimonial {
  const _Testimonial({
    required this.quote,
    required this.name,
    required this.title,
    required this.organization,
    required this.imageAsset,
  });

  final String quote;
  final String name;
  final String title;
  final String organization;
  final String imageAsset;
}

const _testimonials = <_Testimonial>[
  _Testimonial(
    quote:
        'AiClinic keeps our front desk, clinicians, and billing aligned without slowing anyone down. It feels calm even on busy mornings.',
    name: 'Dr. Ahmed Hassan',
    title: 'Medical Director',
    organization: 'Downtown Clinic',
    imageAsset: 'assets/images/auth/testimonial_1.jpg',
  ),
  _Testimonial(
    quote:
        'Patient records, appointments, and invoices finally live in one place. The team adopted it in days, not weeks.',
    name: 'Omar Farouk',
    title: 'Practice Manager',
    organization: 'Nasr City',
    imageAsset: 'assets/images/auth/testimonial_2.jpg',
  ),
  _Testimonial(
    quote:
        'The workflow is focused and predictable. We spend less time hunting for information and more time with patients.',
    name: 'Dr. Karim Mansour',
    title: 'Family Physician',
    organization: 'Alexandria',
    imageAsset: 'assets/images/auth/testimonial_3.jpg',
  ),
];

int _wrapIndex(int min, int max, int value) {
  final rangeSize = max - min;
  return ((((value - min) % rangeSize) + rangeSize) % rangeSize) + min;
}

/// Full-screen sign-in portal (web `LoginPage`).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final FocusNode _passwordFocusNode;
  late final AuthNotifier _authNotifier;
  ProviderSubscription<AuthSessionState>? _authSessionSub;
  final _submitFocusNode = FocusNode();

  var _enterStarted = false;
  var _forgotQueryHandled = false;
  var _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _authNotifier = ref.read(authNotifierProvider.notifier);
    _isAuthenticated = ref.read(authSessionProvider).isAuthenticated;
    _authSessionSub = ref.listenManual(authSessionProvider, (_, next) => _isAuthenticated = next.isAuthenticated);
    _enterController = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.modal));
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode();
    _passwordFocusNode.onKeyEvent = _handlePasswordKeyEvent;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enterStarted) return;
    _enterStarted = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _enterController.duration = AppMotion.resolveDuration(AppMotionPreset.modal, reducedMotion: reducedMotion);
    _enterController.forward();
    _maybeTriggerForgotPasswordFromQuery();
  }

  void _maybeTriggerForgotPasswordFromQuery() {
    if (_forgotQueryHandled) return;

    final queryParameters = GoRouterState.of(context).uri.queryParameters;
    if (!LoginQueryParams.isForgotPasswordIntent(queryParameters)) return;

    _forgotQueryHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showForgotPasswordMessage();
    });
  }

  @override
  void dispose() {
    _authSessionSub?.close();
    if (!_isAuthenticated) {
      final notifier = _authNotifier;
      scheduleMicrotask(() {
        try {
          notifier.resetSignInForm();
        } catch (_) {
          // Provider scope may already be torn down during widget tests.
        }
      });
    }
    _enterController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _submitFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handlePasswordKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clearError() {
    ref.read(authNotifierProvider.notifier).clearSignInError();
  }

  void _submit() {
    ref
        .read(authNotifierProvider.notifier)
        .signIn(username: _usernameController.text, password: _passwordController.text);
  }

  void _devLoginAsAdmin() {
    _usernameController.text = AuthDevBootstrapCredentials.username;
    _passwordController.text = AuthDevBootstrapCredentials.password;
    _submit();
  }

  Future<void> _devFillDummyClinic() async {
    await ShellDevFillDummyClinic.handleNavSelection(context, ref);
  }

  Future<void> _devResetClinic() async {
    await ShellDevResetClinic.handleNavSelection(context, ref);
  }

  void _showForgotPasswordMessage() {
    ref.read(authNotifierProvider.notifier).showForgotPasswordMessage();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: LoginStaticBackdrop()),
          _LoginBackdrop(animation: _enterController),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: FocusScope(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppMotion.animatedPreset(
                                context: context,
                                preset: AppMotionPreset.modal,
                                animation: _enterController,
                                child: _LoginPanel(
                                  authState: authState,
                                  usernameController: _usernameController,
                                  passwordController: _passwordController,
                                  passwordFocusNode: _passwordFocusNode,
                                  submitFocusNode: _submitFocusNode,
                                  onFieldChanged: _clearError,
                                  onForgotPassword: _showForgotPasswordMessage,
                                  onSubmit: _submit,
                                ),
                              ),
                              AuthDevWidgets.panel(
                                onLoginAsAdmin: _devLoginAsAdmin,
                                onFillDummyClinic: _devFillDummyClinic,
                                onResetClinic: _devResetClinic,
                                isSubmitting: authState.isSubmitting,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdropColor = isDark ? AppColorPrimitives.surfaceBackdropDark : AppColorPrimitives.surfaceBackdropLight;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final showBlur = !reducedMotion;

    return FadeTransition(
      opacity: animation,
      child: ExcludeSemantics(
        child: showBlur
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                child: ColoredBox(color: backdropColor),
              )
            : ColoredBox(color: backdropColor),
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.authState,
    required this.usernameController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.submitFocusNode,
    required this.onFieldChanged,
    required this.onForgotPassword,
    required this.onSubmit,
  });

  final AuthUiState authState;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final FocusNode submitFocusNode;
  final VoidCallback onFieldChanged;
  final VoidCallback onForgotPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.min(screenHeight * 0.9, 680.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth >= _lgBreakpoint;

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _lgBreakpoint, maxHeight: maxHeight),
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: Material(
              color: colors.surfaceDefault,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.x2l),
                side: BorderSide(color: colors.borderDefault),
              ),
              child: DecoratedBox(
                decoration: context.appElevation.decoration(
                  level: 3,
                  color: colors.surfaceDefault,
                  borderRadius: BorderRadius.circular(AppRadius.x2l),
                  border: Border.all(color: colors.borderDefault),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.x2l),
                  child: isLarge
                      ? SizedBox(
                          height: maxHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _LoginFormColumn(
                                  fillHeight: true,
                                  authState: authState,
                                  usernameController: usernameController,
                                  passwordController: passwordController,
                                  passwordFocusNode: passwordFocusNode,
                                  submitFocusNode: submitFocusNode,
                                  onFieldChanged: onFieldChanged,
                                  onForgotPassword: onForgotPassword,
                                  onSubmit: onSubmit,
                                ),
                              ),
                              const Expanded(child: _TestimonialCarousel()),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: _LoginFormColumn(
                            authState: authState,
                            usernameController: usernameController,
                            passwordController: passwordController,
                            passwordFocusNode: passwordFocusNode,
                            submitFocusNode: submitFocusNode,
                            onFieldChanged: onFieldChanged,
                            onForgotPassword: onForgotPassword,
                            onSubmit: onSubmit,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoginFormColumn extends StatelessWidget {
  const _LoginFormColumn({
    this.fillHeight = false,
    required this.authState,
    required this.usernameController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.submitFocusNode,
    required this.onFieldChanged,
    required this.onForgotPassword,
    required this.onSubmit,
  });

  final bool fillHeight;
  final AuthUiState authState;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final FocusNode submitFocusNode;
  final VoidCallback onFieldChanged;
  final VoidCallback onForgotPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 640 ? AppSpacing.space8 : AppSpacing.space6;

    final formBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppBrandMark(),
        const SizedBox(height: AppSpacing.space8),
        Semantics(
          header: true,
          child: Text('Welcome back', style: AppTypography.h1(context).copyWith(color: colors.textPrimary)),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Sign in with your clinic credentials to continue.',
          style: AppTypography.body(context).copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        if (authState.errorMessage != null) ...[
          AppAlert(
            variant: authState.isInfoMessage ? AppAlertVariant.info : AppAlertVariant.danger,
            title: authState.errorMessage!,
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: AppFormField(
                      id: 'login-username',
                      label: 'Username',
                      requiredMark: true,
                      child: AppTextInput(
                        id: 'login-username',
                        controller: usernameController,
                        size: AppInputSize.lg,
                        placeholder: 'Enter your username',
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => onFieldChanged(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: AppFormField(
                      id: 'login-password',
                      label: 'Password',
                      requiredMark: true,
                      child: AppPasswordInput(
                        id: 'login-password',
                        controller: passwordController,
                        focusNode: passwordFocusNode,
                        size: AppInputSize.lg,
                        placeholder: 'Enter your password',
                        onChanged: (_) => onFieldChanged(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space6),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: AppButton(
                    variant: AppButtonVariant.link,
                    size: AppButtonSize.md,
                    onPressed: onForgotPassword,
                    child: const Text('Forgot your password?'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: Focus(
                  focusNode: submitFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      onSubmit();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.lg,
                      loading: authState.isSubmitting,
                      onPressed: onSubmit,
                      child: const Text('Log in'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final footer = Text(
      '© AiClinic Health Group',
      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: AppSpacing.space8),
      child: fillHeight
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SingleChildScrollView(child: formBody)),
                footer,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                formBody,
                const SizedBox(height: AppSpacing.space8),
                footer,
              ],
            ),
    );
  }
}

class _TestimonialCarousel extends StatefulWidget {
  const _TestimonialCarousel();

  @override
  State<_TestimonialCarousel> createState() => _TestimonialCarouselState();
}

class _TestimonialCarouselState extends State<_TestimonialCarousel> {
  static const _autoAdvanceInterval = Duration(seconds: 6);

  var _page = 0;
  var _direction = 0;
  var _switchCount = 0;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _scheduleAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(_autoAdvanceInterval, () {
      if (!mounted) return;
      _navigate(1);
    });
  }

  void _navigate(int nextDirection) {
    setState(() {
      _direction = nextDirection;
      _page += nextDirection;
      _switchCount++;
    });
    _scheduleAutoAdvance();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final currentIndex = _wrapIndex(0, _testimonials.length, _page);
    final testimonial = _testimonials[currentIndex];
    final textDirection = Directionality.of(context);
    final previousIcon = textDirection == TextDirection.rtl ? Icons.arrow_forward : Icons.arrow_back;
    final nextIcon = textDirection == TextDirection.rtl ? Icons.arrow_back : Icons.arrow_forward;

    return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _TestimonialImageSwitcher(
              switchKey: _switchCount,
              imageAsset: testimonial.imageAsset,
              duration: reducedMotion ? AppMotion.fast : const Duration(milliseconds: 800),
              reducedMotion: reducedMotion,
              enterOffset: _direction > 0 ? const Offset(0.12, 0) : const Offset(-0.12, 0),
              fallbackColor: colors.surfaceMuted,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x73000000), Colors.transparent],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TestimonialGlassCard(
                      reducedMotion: reducedMotion,
                      switchCount: _switchCount,
                      direction: _direction,
                      testimonial: testimonial,
                      previousIcon: previousIcon,
                      nextIcon: nextIcon,
                      onPrevious: () => _navigate(-1),
                      onNext: () => _navigate(1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
  }
}

class _TestimonialGlassCard extends StatelessWidget {
  const _TestimonialGlassCard({
    required this.reducedMotion,
    required this.switchCount,
    required this.direction,
    required this.testimonial,
    required this.previousIcon,
    required this.nextIcon,
    required this.onPrevious,
    required this.onNext,
  });

  final bool reducedMotion;
  final int switchCount;
  final int direction;
  final _Testimonial testimonial;
  final IconData previousIcon;
  final IconData nextIcon;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final duration = reducedMotion ? AppMotion.fast : const Duration(milliseconds: 800);
    final enterOffset = direction > 0 ? const Offset(0.12, 0) : const Offset(-0.12, 0);

    final glassContent = Padding(
      padding: const EdgeInsets.all(AppSpacing.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TestimonialSlideSwitcher(
            switchKey: switchCount,
            duration: duration,
            reducedMotion: reducedMotion,
            enterOffset: enterOffset,
            child: Text(testimonial.quote, style: AppTypography.h2(context).copyWith(color: Colors.white)),
          ),
          const SizedBox(height: AppSpacing.space6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TestimonialSlideSwitcher(
                  switchKey: switchCount,
                  duration: duration,
                  reducedMotion: reducedMotion,
                  enterOffset: enterOffset,
                  child: Text(testimonial.name, style: AppTypography.bodyStrong(context).copyWith(color: Colors.white)),
                ),
              ),
              const SizedBox(width: AppSpacing.space4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (_) => const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.space05),
                    child: Icon(Icons.star, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TestimonialSlideSwitcher(
                  switchKey: switchCount,
                  duration: duration,
                  reducedMotion: reducedMotion,
                  enterOffset: enterOffset,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(testimonial.title, style: AppTypography.bodyStrong(context).copyWith(color: Colors.white)),
                      Text(
                        testimonial.organization,
                        style: AppTypography.bodySm(context).copyWith(color: const Color(0xD9FFFFFF)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              _CarouselNavButton(icon: previousIcon, label: 'Previous testimonial', onPressed: onPrevious),
              const SizedBox(width: AppSpacing.space2),
              _CarouselNavButton(icon: nextIcon, label: 'Next testimonial', onPressed: onNext),
            ],
          ),
        ],
      ),
    );

    final radius = BorderRadius.circular(AppRadius.x2l);
    if (reducedMotion) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: radius,
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: glassContent,
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x40000000),
            borderRadius: radius,
            border: Border.all(color: const Color(0x4DFFFFFF)),
          ),
          child: glassContent,
        ),
      ),
    );
  }
}

/// Full-bleed carousel image transition (matches [_TestimonialSlideSwitcher]).
class _TestimonialImageSwitcher extends StatelessWidget {
  const _TestimonialImageSwitcher({
    required this.switchKey,
    required this.imageAsset,
    required this.duration,
    required this.reducedMotion,
    required this.enterOffset,
    required this.fallbackColor,
  });

  final int switchKey;
  final String imageAsset;
  final Duration duration;
  final bool reducedMotion;
  final Offset enterOffset;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) {
      return Image(
        key: ValueKey<int>(switchKey),
        image: AssetImage(imageAsset),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return ColoredBox(color: fallbackColor);
        },
      );
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: const Cubic(0.2, 0, 0.2, 1),
      switchOutCurve: const Cubic(0.8, 0, 0.8, 1),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final child in previousChildren) Positioned.fill(child: child),
            if (currentChild != null) Positioned.fill(child: currentChild),
          ],
        );
      },
      transitionBuilder: (child, animation) => _testimonialSlideTransition(
        child: child,
        animation: animation,
        reducedMotion: reducedMotion,
        enterOffset: enterOffset,
      ),
      child: Image(
        key: ValueKey<int>(switchKey),
        image: AssetImage(imageAsset),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return ColoredBox(color: fallbackColor);
        },
      ),
    );
  }
}

/// Left-aligned carousel text transition (web `AnimatePresence mode="popLayout"`).
class _TestimonialSlideSwitcher extends StatelessWidget {
  const _TestimonialSlideSwitcher({
    required this.switchKey,
    required this.duration,
    required this.reducedMotion,
    required this.enterOffset,
    required this.child,
  });

  final int switchKey;
  final Duration duration;
  final bool reducedMotion;
  final Offset enterOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) {
      return ClipRect(
        child: SizedBox(key: ValueKey<int>(switchKey), width: double.infinity, child: child),
      );
    }

    return ClipRect(
      child: AnimatedSize(
        duration: reducedMotion ? Duration.zero : duration,
        curve: const Cubic(0.2, 0, 0.2, 1),
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: const Cubic(0.2, 0, 0.2, 1),
          switchOutCurve: const Cubic(0.8, 0, 0.8, 1),
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: AlignmentDirectional.topStart,
              clipBehavior: Clip.hardEdge,
              children: [
                for (final child in previousChildren) Positioned(top: 0, left: 0, right: 0, child: child),
                ?currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) => _testimonialSlideTransition(
            child: child,
            animation: animation,
            reducedMotion: reducedMotion,
            enterOffset: enterOffset,
            alignStart: true,
          ),
          child: SizedBox(key: ValueKey<int>(switchKey), width: double.infinity, child: child),
        ),
      ),
    );
  }
}

Widget _testimonialSlideTransition({
  required Widget child,
  required Animation<double> animation,
  required bool reducedMotion,
  required Offset enterOffset,
  bool alignStart = false,
}) {
  if (reducedMotion) {
    return FadeTransition(opacity: animation, child: child);
  }

  final curved = CurvedAnimation(
    parent: animation,
    curve: const Cubic(0.2, 0, 0.2, 1),
    reverseCurve: const Cubic(0.8, 0, 0.8, 1),
  );

  final transitioned = FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(begin: enterOffset, end: Offset.zero).animate(curved),
      child: alignStart ? Align(alignment: AlignmentDirectional.topStart, child: child) : child,
    ),
  );

  return transitioned;
}

class _CarouselNavButton extends StatefulWidget {
  const _CarouselNavButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_CarouselNavButton> createState() => _CarouselNavButtonState();
}

class _CarouselNavButtonState extends State<_CarouselNavButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _hovered ? const Color(0xB3FFFFFF) : const Color(0x80FFFFFF);

    return Semantics(
      button: true,
      label: widget.label,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPressed,
          customBorder: const CircleBorder(),
          onHover: (hovered) => setState(() => _hovered = hovered),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor),
            ),
            child: Icon(widget.icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
