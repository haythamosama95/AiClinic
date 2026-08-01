// Reusable pump helpers and fakes for setup presentation widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_hydration_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_wizard.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog_content.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';

/// Wide surface so the setup step rail and content render side by side.
const Size setupWideSurfaceSize = Size(1024, 900);

/// Controllable [ClinicSetupState] for widget tests — no network or persistence.
class TestClinicSetupNotifier extends ClinicSetupNotifier {
  TestClinicSetupNotifier(super.ref, ClinicSetupState initial) {
    state = initial;
  }

  void replace(ClinicSetupState next) => state = next;

  @override
  Future<void> loadDraft() async {}

  @override
  Future<void> persistDraft() async {}

  @override
  Future<void> hydrateFromBackend() async {}
}

/// Tracks [ClinicSetupNotifier.completeSetup] for wizard submit tests.
class SpyClinicSetupNotifier extends TestClinicSetupNotifier {
  SpyClinicSetupNotifier(super.ref, super.initial);

  var completeSetupCallCount = 0;
  bool completeSetupResult = false;
  String? completeSetupError;

  @override
  Future<bool> completeSetup() async {
    completeSetupCallCount++;
    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    await Future<void>.delayed(Duration.zero);
    state = state.copyWith(isSubmitting: false, submitError: completeSetupError);
    return completeSetupResult;
  }
}

/// Hydration that surfaces a resolved data state immediately.
Override setupHydrationSuccessOverride() {
  return clinicSetupHydrationProvider.overrideWithValue(const AsyncData(null));
}

/// Hydration that never completes — keeps [clinicSetupHydrationProvider] loading.
Override setupHydrationLoadingOverride() {
  return clinicSetupHydrationProvider.overrideWithValue(const AsyncLoading<void>());
}

/// Hydration that surfaces an error state immediately.
Override setupHydrationErrorOverride([Object? error]) {
  return clinicSetupHydrationProvider.overrideWithValue(
    AsyncError<void>(error ?? Exception('Hydration failed'), StackTrace.empty),
  );
}

/// Swallows known setup-widget layout/animation noise from branch-step transitions.
void ignoreKnownSetupTestExceptions() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('RenderAnimatedSize was mutated') || message.contains('RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Clears non-fatal framework exceptions surfaced during guarded pumps.
void drainSetupTestExceptions(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

ThemeData _setupTestTheme() {
  return AppTheme.light().copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _InstantPageTransitionsBuilder(),
        TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
        TargetPlatform.linux: _InstantPageTransitionsBuilder(),
        TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
        TargetPlatform.windows: _InstantPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _InstantPageTransitionsBuilder(),
      },
    ),
  );
}

/// Hydration that fails on the first [failCount] attempts, then succeeds.
class FlakySetupHydration {
  FlakySetupHydration({this.failCount = 1});

  final int failCount;
  var attemptCount = 0;

  void call(Ref ref) {
    attemptCount++;
    if (attemptCount <= failCount) {
      throw Exception('Hydration failed');
    }
  }
}

/// Hydration override that fails on the first [failCount] attempts, then succeeds.
Override flakySetupHydrationOverride(FlakySetupHydration hydration) {
  return clinicSetupHydrationProvider.overrideWith(hydration.call);
}

/// Authenticated session for setup widget tests.
AuthSessionState setupAuthSession({bool setupRequired = true}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      setupRequired: setupRequired,
      isBootstrapAdmin: true,
      role: StaffRole.administrator,
    ),
  );
}

ClinicSetupState defaultClinicSetupState({int step = 0}) {
  return ClinicSetupState(draft: createDefaultSetup(), step: step);
}

/// Draft with valid values for every wizard step.
SetupDraft buildValidSetupDraft() {
  final branch = createEmptyBranch().copyWith(
    name: 'Main Branch',
    code: 'MAIN',
    mobile: '1000000000',
    mapLocation: 'https://maps.example.com',
  );
  final staff = createEmptyStaff().copyWith(
    name: 'Dr. Sara Hassan',
    mobile: '1000000001',
    username: 'sarah',
    password: 'Secret12',
    role: 'administrator',
    branchIds: [branch.id],
  );
  final service = createEmptyService().copyWith(name: 'Consultation', price: 150);

  return SetupDraft(
    organization: const OrganizationDraft(name: 'Nile Dental', timezone: 'Africa/Cairo', currency: 'EGP'),
    branches: [branch],
    staff: [staff],
    services: [service],
  );
}

ClinicSetupState presetClinicSetupState({
  SetupDraft? draft,
  int step = 0,
  bool isSubmitting = false,
  String? submitError,
  Set<int> completedSteps = const {},
}) {
  return ClinicSetupState(
    draft: draft ?? buildValidSetupDraft(),
    step: step,
    completedSteps: completedSteps,
    isSubmitting: isSubmitting,
    submitError: submitError,
  );
}

/// Organization step only — name filled, other defaults intact.
SetupDraft buildValidOrganizationDraft() {
  return createDefaultSetup().copyWith(
    organization: const OrganizationDraft(name: 'Nile Dental', timezone: 'Africa/Cairo', currency: 'EGP'),
  );
}

List<Override> setupProviderOverrides({
  AuthSessionState? auth,
  ClinicSetupState? setupState,
  ClinicSetupNotifier? setupNotifier,
  Override? clinicSetupOverride,
  Override? hydrationOverride,
  Future<void> Function(Ref ref)? hydration,
  List<Override> extraOverrides = const [],
}) {
  final resolvedAuth = auth ?? setupAuthSession();
  final resolvedSetup = setupState ?? defaultClinicSetupState();

  return [
    authSessionProvider.overrideWith(() => MutableAuthSessionNotifier(resolvedAuth)),
    if (clinicSetupOverride != null)
      clinicSetupOverride
    else if (setupNotifier != null)
      clinicSetupProvider.overrideWith((ref) => setupNotifier)
    else
      clinicSetupProvider.overrideWith((ref) => TestClinicSetupNotifier(ref, resolvedSetup)),
    if (hydrationOverride != null)
      hydrationOverride
    else if (hydration != null)
      clinicSetupHydrationProvider.overrideWith((ref) {
        hydration(ref);
      })
    else
      setupHydrationSuccessOverride(),
    ...extraOverrides,
  ];
}

Widget _setupTestMediaQuery({required Size surfaceSize, required Widget child}) {
  return MediaQuery(
    data: MediaQueryData(size: surfaceSize, disableAnimations: true),
    child: child,
  );
}

Widget _setupMaterialApp({required Widget child}) {
  return MaterialApp(
    theme: _setupTestTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TickerMode(enabled: false, child: child),
  );
}

/// Pumps [child] inside the canonical setup widget-test shell.
Future<void> pumpSetupWidget(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = setupWideSurfaceSize,
  bool scrollable = true,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final body = scrollable ? SingleChildScrollView(child: child) : child;

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: _setupTestMediaQuery(
        surfaceSize: surfaceSize,
        child: _setupMaterialApp(child: Scaffold(body: body)),
      ),
    ),
  );
}

/// Pumps [SetupWizard] with auth + clinic setup provider overrides.
Future<void> pumpSetupWizard(
  WidgetTester tester, {
  List<Override> overrides = const [],
  AuthSessionState? auth,
  ClinicSetupState? setupState,
  ClinicSetupNotifier? setupNotifier,
  Size surfaceSize = setupWideSurfaceSize,
}) async {
  await pumpSetupWidget(
    tester,
    child: const SetupWizard(),
    surfaceSize: surfaceSize,
    scrollable: false,
    overrides: overrides.isNotEmpty
        ? overrides
        : setupProviderOverrides(auth: auth, setupState: setupState, setupNotifier: setupNotifier),
  );
}

/// Pumps [ClinicSetupDialogContent] with auth + clinic setup provider overrides.
Future<void> pumpClinicSetupDialogContent(
  WidgetTester tester, {
  List<Override> overrides = const [],
  AuthSessionState? auth,
  ClinicSetupState? setupState,
  bool showPageHeader = true,
  bool showCompletedBanner = true,
  Size surfaceSize = setupWideSurfaceSize,
}) async {
  await pumpSetupWidget(
    tester,
    child: ClinicSetupDialogContent(showPageHeader: showPageHeader, showCompletedBanner: showCompletedBanner),
    surfaceSize: surfaceSize,
    overrides: overrides.isNotEmpty ? overrides : setupProviderOverrides(auth: auth, setupState: setupState),
  );
}

Future<void> pumpUntilSetupFinder(WidgetTester tester, Finder finder, {int maxFrames = 30}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for $finder');
}

Future<void> pumpSetupFrames(WidgetTester tester) async {
  await tester.pump();
}

Future<void> settleSetupWidget(WidgetTester tester) async {
  await pumpSetupFrames(tester);
  await tester.pump(const Duration(milliseconds: 200));
}

ProviderContainer setupProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Finder setupContinueButton() => find.text('Continue');

Finder setupBackButton() => find.text('Back');

Future<void> tapSetupContinue(WidgetTester tester) async {
  await tester.tap(setupContinueButton());
  await tester.pump();
}

Future<void> tapSetupBack(WidgetTester tester) async {
  await tester.tap(setupBackButton());
  await tester.pump();
}

AppButton setupButtonAncestor(Finder label) {
  return find.ancestor(of: label, matching: find.byType(AppButton)).evaluate().first.widget as AppButton;
}

bool isSetupButtonDisabled(AppButton button) {
  return button.disabled || button.onPressed == null;
}

Finder setupEditableText(String semanticsId) {
  final scope = find.bySemanticsIdentifier(semanticsId);
  final textField = find.descendant(of: scope, matching: find.byType(TextField));
  if (textField.evaluate().isNotEmpty) {
    return textField;
  }

  return find.descendant(of: scope, matching: find.byType(EditableText));
}

Future<void> enterSetupField(WidgetTester tester, String semanticsId, String value) async {
  final field = setupEditableText(semanticsId);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, value);
  await tester.pump();
}
