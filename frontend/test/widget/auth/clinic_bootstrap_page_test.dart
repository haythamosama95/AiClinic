import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/pages/clinic_bootstrap_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _BootstrapAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => _bootstrapAdminSession();
}

class _BootstrapCompleteAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => _bootstrapAdminSession(setupRequired: false);
}

class _TestBootstrapNotifier extends BootstrapNotifier {
  _TestBootstrapNotifier({this.failFinishSetup = false, this.initialState = const BootstrapUiState()});

  final bool failFinishSetup;
  final BootstrapUiState initialState;
  int continueCalls = 0;
  int finishSetupCalls = 0;

  @override
  BootstrapUiState build() => initialState;

  @override
  bool continueToBranchStep({
    required String name,
    String? logoUrl,
    required String currencyCode,
    required String timezone,
  }) {
    continueCalls++;
    state = state.copyWith(
      step: BootstrapWizardStep.branch,
      organizationDraft: BootstrapOrganizationDraft(
        name: name.trim(),
        logoUrl: logoUrl?.trim().isEmpty == true ? null : logoUrl?.trim(),
        currencyCode: currencyCode.trim().toUpperCase(),
        timezone: timezone.trim(),
      ),
    );
    return true;
  }

  @override
  Future<bool> finishSetup({
    required String branchName,
    required String branchCode,
    required String address,
    required String phone,
    required String mapsUrl,
  }) async {
    finishSetupCalls++;
    if (failFinishSetup) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'An organization already exists for this installation.',
      );
      return false;
    }

    state = state.copyWith(
      isSubmitting: false,
      organizationId: 'org-test-uuid',
      branchId: 'branch-test-uuid',
      step: BootstrapWizardStep.complete,
    );
    return true;
  }
}

AuthSessionState _bootstrapAdminSession({bool setupRequired = true}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: AuthSessionContext(
      staffProfile: const StaffProfile(
        staffMemberId: 'b0000000-0000-4000-8000-000000000001',
        fullName: 'Clinic Administrator',
        role: StaffRole.administrator,
        isBootstrapAdmin: true,
        isActive: true,
      ),
      organizationId: setupRequired ? null : 'org-test-uuid',
      branchIds: setupRequired ? const [] : const ['branch-test-uuid'],
      activeBranchId: setupRequired ? null : 'branch-test-uuid',
      permissions: const {},
      setupRequired: setupRequired,
    ),
  );
}

Future<void> _tapScrollable(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 80, scrollable: find.byType(Scrollable).first);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Widget _bootstrapHarness({
  required Widget child,
  BootstrapNotifier? bootstrapNotifier,
  bool skipPasswordWarning = true,
}) {
  final bootstrap =
      bootstrapNotifier ??
      _TestBootstrapNotifier(initialState: BootstrapUiState(hasShownPasswordWarning: skipPasswordWarning));

  return ProviderScope(
    overrides: [
      startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
      authSessionProvider.overrideWith(_BootstrapAuthNotifier.new),
      bootstrapNotifierProvider.overrideWith(() => bootstrap),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => child),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: AppRoutes.staffCreate,
            builder: (context, state) => const Scaffold(body: Text('Staff create')),
          ),
        ],
        initialLocation: AppRoutes.bootstrap,
      ),
    ),
  );
}

void main() {
  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  setUp(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1280, 1600);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  group('ClinicBootstrapPage', () {
    testWidgets('renders organization step with required field', (tester) async {
      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage()));
      await tester.pumpAndSettle();

      expect(find.text('Set up your clinic'), findsOneWidget);
      expect(find.text('Organization name'), findsOneWidget);
      expect(find.text('Continue to branch'), findsOneWidget);
    });

    testWidgets('shows first sign-in password warning for bootstrap admin', (tester) async {
      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), skipPasswordWarning: false));
      await tester.pumpAndSettle();

      expect(find.text('Change the default password'), findsOneWidget);
      await tester.tap(find.text('Continue to clinic setup'));
      await tester.pumpAndSettle();

      expect(find.text('Change the default password'), findsNothing);
    });

    testWidgets('does not re-show password warning after dismissed', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      expect(find.text('Change the default password'), findsNothing);
    });

    testWidgets('empty organization name shows validation without RPC call', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Continue to branch'));

      expect(bootstrap.continueCalls, 0);
      expect(find.text('Organization name is required'), findsOneWidget);
    });

    testWidgets('rejects organization name consisting only of spaces', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '     ');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Continue to branch'));

      expect(bootstrap.continueCalls, 0);
      expect(find.text('Organization name is required'), findsOneWidget);
    });

    testWidgets('currency dropdown selection fills the text field', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sunrise Clinic');
      await tester.tap(find.byKey(const ValueKey('bootstrap_currency')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('bootstrap_currency')), 'EG');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ListTile, 'EGP'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('bootstrap_currency')), findsOneWidget);
      final currencyField = tester.widget<TextFormField>(find.byKey(const ValueKey('bootstrap_currency')));
      expect(currencyField.controller?.text, 'EGP');
    });

    testWidgets('successful organization step advances to branch step without RPC', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sunrise Clinic');
      await tester.enterText(find.byKey(const ValueKey('bootstrap_currency')), 'EGP');
      await tester.enterText(find.byKey(const ValueKey('bootstrap_timezone')), 'Africa/Cairo');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Continue to branch'));

      expect(bootstrap.continueCalls, 1);
      expect(bootstrap.finishSetupCalls, 0);
      expect(find.text('Branch name'), findsOneWidget);
      expect(find.text('Finish setup'), findsOneWidget);
    });

    testWidgets('back from branch after continue does not show org already exists', (tester) async {
      final bootstrap = _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true));

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sunrise Clinic');
      await tester.enterText(find.byKey(const ValueKey('bootstrap_currency')), 'USD');
      await tester.enterText(find.byKey(const ValueKey('bootstrap_timezone')), 'UTC');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Continue to branch'));
      await _tapScrollable(tester, find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsNothing);
      expect(bootstrap.finishSetupCalls, 0);
    });

    testWidgets('branch step back returns to organization step', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.branch,
          organizationDraft: BootstrapOrganizationDraft(
            name: 'Sunrise Clinic',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await _tapScrollable(tester, find.text('Back'));

      expect(find.text('Organization name'), findsOneWidget);
    });

    testWidgets('empty branch name blocks finish without RPC', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.branch,
          organizationDraft: BootstrapOrganizationDraft(
            name: 'Sunrise Clinic',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Finish setup'));

      expect(bootstrap.finishSetupCalls, 0);
      expect(find.text('Branch name is required.'), findsOneWidget);
    });

    testWidgets('successful branch step shows completion actions', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.branch,
          organizationDraft: BootstrapOrganizationDraft(
            name: 'Sunrise Clinic',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Main Branch');
      await tester.enterText(find.byType(TextFormField).at(1), 'MAIN');
      await tester.enterText(find.byType(TextFormField).at(2), '123 Main St');
      await tester.enterText(find.byType(TextFormField).at(3), '+1-555-0100');
      await tester.enterText(find.byType(TextFormField).at(4), 'https://maps.example/main');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Finish setup'));

      expect(bootstrap.finishSetupCalls, 1);
      expect(find.text('Clinic setup is complete'), findsOneWidget);
      expect(find.text('Create staff accounts'), findsOneWidget);
      expect(find.text('Go to clinic home'), findsOneWidget);
    });

    testWidgets('completion navigates to home', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.complete,
          organizationId: 'org-test-uuid',
          branchId: 'branch-test-uuid',
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await _tapScrollable(tester, find.text('Go to clinic home'));

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('completion navigates to staff create route', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.complete,
          organizationId: 'org-test-uuid',
          branchId: 'branch-test-uuid',
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await _tapScrollable(tester, find.text('Create staff accounts'));

      expect(find.text('Staff create'), findsOneWidget);
    });

    testWidgets('finish setup failure shows error banner', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        failFinishSetup: true,
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.branch,
          organizationDraft: BootstrapOrganizationDraft(
            name: 'Sunrise Clinic',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Main Branch');
      await tester.enterText(find.byType(TextFormField).at(1), 'MAIN');
      await tester.enterText(find.byType(TextFormField).at(2), '123 Main St');
      await tester.enterText(find.byType(TextFormField).at(3), '+1-555-0100');
      await tester.enterText(find.byType(TextFormField).at(4), 'https://maps.example/main');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Finish setup'));

      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('dismiss error banner clears message', (tester) async {
      final bootstrap = _TestBootstrapNotifier(
        initialState: const BootstrapUiState(
          step: BootstrapWizardStep.branch,
          errorMessage: 'Unable to save clinic setup. Check connectivity and try again.',
          hasShownPasswordWarning: true,
        ),
      );

      await tester.pumpWidget(_bootstrapHarness(child: const ClinicBootstrapPage(), bootstrapNotifier: bootstrap));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to save clinic setup'), findsNothing);
    });

    testWidgets('setup complete session redirects bootstrap wizard to home (US6)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
            authSessionProvider.overrideWith(_BootstrapCompleteAuthNotifier.new),
            bootstrapNotifierProvider.overrideWith(
              () => _TestBootstrapNotifier(initialState: const BootstrapUiState(hasShownPasswordWarning: true)),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => const ClinicBootstrapPage()),
                GoRoute(
                  path: AppRoutes.home,
                  builder: (context, state) => const Scaffold(body: Text('Home')),
                ),
              ],
              initialLocation: AppRoutes.bootstrap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Clinic setup'), findsNothing);
    });
  });
}
