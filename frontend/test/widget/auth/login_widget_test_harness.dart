// Reusable pump helpers and fakes for [LoginPage] widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/login_query_params.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_brand_mark.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart' as domain;
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';

/// Matches [_lgBreakpoint] in `login_page.dart` (panel switches to side-by-side layout).
const double loginLgBreakpoint = 960;

/// Wide surface so the login panel lays out the testimonial carousel column.
const Size loginWideSurfaceSize = Size(1400, 900);

/// Narrow surface so only the form column is shown (no carousel).
const Size loginNarrowSurfaceSize = Size(600, 900);

/// First testimonial copy (carousel index 0).
const loginFirstTestimonialName = 'Dr. Ahmed Hassan';

/// Last testimonial copy (carousel index 2).
const loginLastTestimonialName = 'Dr. Karim Mansour';

/// Middle testimonial copy (carousel index 1).
const loginMiddleTestimonialName = 'Omar Farouk';

/// The carousel schedules a one-shot [Timer] every six seconds for auto-advance.
/// Widget tests must dispose [LoginPage] before that fires (see [disposeLoginSurface])
/// or advance time explicitly with [tester.pump].
const Duration loginCarouselAutoAdvanceInterval = Duration(seconds: 6);

/// Records [domain.AuthRepository.signIn] calls without touching Supabase.
class RecordingAuthRepository implements domain.AuthRepository {
  RecordingAuthRepository({this.onSignIn});

  final void Function(String username, String password)? onSignIn;

  int signInCallCount = 0;
  String? lastUsername;
  String? lastPassword;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Future<void> clearPersistedSessionOnColdStart() async {}

  @override
  Future<void> refreshSession() async {}

  @override
  Future<void> signIn({required String username, required String password}) async {
    signInCallCount++;
    lastUsername = username;
    lastPassword = password;
    onSignIn?.call(username, password);
  }

  @override
  Future<void> signOut() async {}
}

/// [RecordingAuthRepository] that does not complete until [releaseSignIn] is called.
class HangingAuthRepository extends RecordingAuthRepository {
  final Completer<void> _signInGate = Completer<void>();

  Future<void> get waitForSignIn => _signInGate.future;

  void releaseSignIn() {
    if (!_signInGate.isCompleted) {
      _signInGate.complete();
    }
  }

  @override
  Future<void> signIn({required String username, required String password}) async {
    await super.signIn(username: username, password: password);
    await _signInGate.future;
  }
}

/// Auth session notifier that authenticates when [syncAfterSignIn] runs.
class SignInCapturingSessionNotifier extends TestAuthSessionNotifier {
  var authenticateOnSync = true;

  @override
  Future<void> syncAfterSignIn() async {
    if (authenticateOnSync) {
      setAuthenticated();
    }
  }
}

/// Replaces [AuthNotifier] with a fixed [AuthUiState] for presentation tests.
class TestAuthUiNotifier extends AuthNotifier {
  TestAuthUiNotifier(this._state);

  AuthUiState _state;

  @override
  AuthUiState build() => _state;

  void replaceState(AuthUiState next) {
    _state = next;
    state = next;
  }
}

/// Values produced by [pumpLoginPage] / [pumpLoginRouter].
class LoginPumpResult {
  const LoginPumpResult({
    required this.sessionNotifier,
    required this.authRepository,
  });

  final TestAuthSessionNotifier sessionNotifier;
  final RecordingAuthRepository authRepository;
}

List<Override> loginProviderOverrides({
  TestAuthSessionNotifier? sessionNotifier,
  RecordingAuthRepository? authRepository,
  AuthUiState? authUiState,
  List<Override> extraOverrides = const [],
}) {
  final session = sessionNotifier ?? TestAuthSessionNotifier();
  final repository = authRepository ?? RecordingAuthRepository();

  return [
    authSessionProvider.overrideWith(() => session),
    authRepositoryProvider.overrideWith((ref) => repository),
    if (authUiState != null)
      authNotifierProvider.overrideWith(
        () => TestAuthUiNotifier(authUiState),
      ),
    ...extraOverrides,
  ];
}

/// Silences image decode failures from decorative login assets.
///
/// Testimonial images already use `errorBuilder`, but the framework can still
/// report image-load diagnostics; this keeps those from failing tests.
void installLoginImageExceptionSilencer() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service') {
      return;
    }
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
}

/// Disposes [LoginPage] so carousel timers are cancelled in [State.dispose].
Future<void> disposeLoginSurface(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

/// Pumps a few frames without waiting for the carousel auto-advance timer.
Future<void> pumpLoginFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void registerLoginSurfaceTearDown(WidgetTester tester) {
  addTearDown(() async {
    await disposeLoginSurface(tester);
  });
}

Widget _loginTestMediaQuery({required Size surfaceSize, required Widget child}) {
  return MediaQuery(
    data: MediaQueryData(size: surfaceSize, disableAnimations: true),
    child: child,
  );
}

Widget _loginRouterMaterialApp({required GoRouter router}) {
  return MaterialApp.router(
    theme: AppTheme.light(),
    builder: (context, appChild) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: appChild!,
      );
    },
    routerConfig: router,
  );
}

GoRouter createLoginTestRouter({
  String initialLocation = AppRoutes.login,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Home stub')),
      ),
    ],
  );
}

/// Pumps [LoginPage] inside a plain [MaterialApp] (no router).
Future<LoginPumpResult> pumpLoginPage(
  WidgetTester tester, {
  Size surfaceSize = loginWideSurfaceSize,
  TestAuthSessionNotifier? sessionNotifier,
  RecordingAuthRepository? authRepository,
  AuthUiState? authUiState,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  registerLoginSurfaceTearDown(tester);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final session = sessionNotifier ?? TestAuthSessionNotifier();
  final repository = authRepository ?? RecordingAuthRepository();
  final router = createLoginTestRouter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: loginProviderOverrides(
        sessionNotifier: session,
        authRepository: repository,
        authUiState: authUiState,
        extraOverrides: extraOverrides,
      ),
      child: _loginTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _loginRouterMaterialApp(router: router),
      ),
    ),
  );

  await pumpLoginFrames(tester);
  return LoginPumpResult(sessionNotifier: session, authRepository: repository);
}

/// Pumps [LoginPage] behind a real [GoRouter] for query-parameter behavior.
Future<LoginPumpResult> pumpLoginRouter(
  WidgetTester tester, {
  String initialLocation = AppRoutes.login,
  Size surfaceSize = loginWideSurfaceSize,
  TestAuthSessionNotifier? sessionNotifier,
  RecordingAuthRepository? authRepository,
  AuthUiState? authUiState,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  registerLoginSurfaceTearDown(tester);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final session = sessionNotifier ?? TestAuthSessionNotifier();
  final repository = authRepository ?? RecordingAuthRepository();
  final router = createLoginTestRouter(initialLocation: initialLocation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: loginProviderOverrides(
        sessionNotifier: session,
        authRepository: repository,
        authUiState: authUiState,
        extraOverrides: extraOverrides,
      ),
      child: _loginTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _loginRouterMaterialApp(router: router),
      ),
    ),
  );

  await pumpLoginFrames(tester);
  return LoginPumpResult(sessionNotifier: session, authRepository: repository);
}

/// Pumps both responsive layouts in one test (wide then narrow).
Future<LoginPumpResult> pumpLoginBothLayouts(
  WidgetTester tester, {
  TestAuthSessionNotifier? sessionNotifier,
  RecordingAuthRepository? authRepository,
  AuthUiState? authUiState,
}) async {
  final result = await pumpLoginPage(
    tester,
    surfaceSize: loginWideSurfaceSize,
    sessionNotifier: sessionNotifier,
    authRepository: authRepository,
    authUiState: authUiState,
  );
  expect(tester.takeException(), isNull);

  await pumpLoginPage(
    tester,
    surfaceSize: loginNarrowSurfaceSize,
    sessionNotifier: sessionNotifier,
    authRepository: authRepository,
    authUiState: authUiState,
  );
  expect(tester.takeException(), isNull);
  return result;
}

ProviderContainer loginProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

AuthUiState readAuthUiState(WidgetTester tester) {
  return loginProviderContainer(tester).read(authNotifierProvider);
}

AuthNotifier readAuthNotifier(WidgetTester tester) {
  return loginProviderContainer(tester).read(authNotifierProvider.notifier);
}

List<Override> authUiStateOverride(AuthUiState state) {
  return [
    authNotifierProvider.overrideWith(() => TestAuthUiNotifier(state)),
  ];
}

Finder loginUsernameField() {
  return find.descendant(
    of: find.ancestor(of: find.text('Username'), matching: find.byType(AppFormField)),
    matching: find.byType(TextField),
  );
}

Finder loginPasswordField() {
  return find.descendant(
    of: find.ancestor(of: find.text('Password'), matching: find.byType(AppFormField)),
    matching: find.byType(TextField),
  );
}

Finder loginSubmitButton() => find.widgetWithText(AppButton, 'Log in');

Finder loginForgotPasswordControl() => find.text('Forgot your password?');

Finder loginBrandMark() => find.byType(AppBrandMark);

Finder loginCarouselNextButton() => find.bySemanticsLabel('Next testimonial');

Finder loginCarouselPreviousButton() => find.bySemanticsLabel('Previous testimonial');

Finder loginPasswordVisibilityToggle() => find.bySemanticsLabel('Show password');

bool loginPasswordIsObscured(WidgetTester tester) {
  return tester.widget<TextField>(loginPasswordField()).obscureText;
}

bool loginSubmitButtonIsLoading(WidgetTester tester) {
  return tester.widget<AppButton>(loginSubmitButton()).loading;
}

bool loginSubmitButtonIsEnabled(WidgetTester tester) {
  final semantics = tester.getSemantics(loginSubmitButton());
  return semantics.flagsCollection.isEnabled == Tristate.isTrue;
}

Future<void> enterLoginCredentials(
  WidgetTester tester, {
  required String username,
  required String password,
}) async {
  await tester.enterText(loginUsernameField(), username);
  await tester.pump();
  await tester.enterText(loginPasswordField(), password);
  await tester.pump();
}

Future<void> tapLoginSubmit(WidgetTester tester) async {
  await tester.tap(loginSubmitButton());
  await tester.pump();
}

Future<void> triggerPasswordFieldEnter(WidgetTester tester) async {
  await tester.tap(loginPasswordField());
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<void> triggerUsernameFieldNext(WidgetTester tester) async {
  await tester.tap(loginUsernameField());
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.next);
  await tester.pump();
}

Future<void> navigateAwayFromLogin(WidgetTester tester) async {
  final router = GoRouter.of(tester.element(find.byType(LoginPage)));
  router.go('/home');
  await tester.pumpAndSettle();
}

String loginRouteWithForgotPasswordIntent() => LoginQueryParams.loginWithForgotPasswordIntent();
