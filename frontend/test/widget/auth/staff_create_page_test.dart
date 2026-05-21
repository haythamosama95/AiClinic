import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/presentation/pages/staff_create_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _OwnerAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.owner, branchIds: const ['branch-test-uuid']),
  );
}

class _DoctorAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.doctor),
  );
}

class _AdministratorAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.administrator, branchIds: const ['branch-test-uuid']),
  );
}

class _BootstrapAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: AuthSessionContext(
      staffProfile: const StaffProfile(
        staffMemberId: 'b0000000-0000-4000-8000-000000000001',
        fullName: 'Clinic Administrator',
        role: StaffRole.administrator,
        isBootstrapAdmin: true,
        isActive: true,
      ),
      organizationId: 'org-test-uuid',
      branchIds: const ['branch-test-uuid'],
      activeBranchId: 'branch-test-uuid',
      permissions: const {},
      setupRequired: false,
    ),
  );
}

const _testBranch = BranchSummary(
  id: 'branch-test-uuid',
  name: 'Main Branch',
  code: 'MAIN',
  address: '123 Clinic St, Cairo',
  phone: '+20 100 000 0000',
  mapsUrl: 'https://maps.example/main',
);

class _TestProvisioningNotifier extends ProvisioningNotifier {
  _TestProvisioningNotifier({this.failCreate = false, this.ownerAlreadyExists = false, this.initialState});

  final bool failCreate;
  final bool ownerAlreadyExists;
  final ProvisioningUiState? initialState;
  int createCalls = 0;

  @override
  ProvisioningUiState build() => initialState ?? ProvisioningUiState(ownerAlreadyExists: ownerAlreadyExists);

  @override
  Future<CreateStaffAccountResult?> createStaffAccount({
    required String username,
    required String fullName,
    required StaffRole role,
    required List<String> branchIds,
    required String password,
    String? primaryBranchId,
  }) async {
    createCalls++;
    if (username.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Username is required.');
      return null;
    }

    if (failCreate) {
      state = state.copyWith(errorMessage: 'Only existing owners may create additional owner accounts.');
      return null;
    }

    state = state.copyWith(
      lastCreated: CreateStaffAccountResult(
        staffMemberId: 'new-staff-uuid',
        username: username.trim().toLowerCase(),
        assignedPassword: password,
      ),
    );
    if (role == StaffRole.owner) {
      state = state.copyWith(ownerAlreadyExists: true);
    }
    return state.lastCreated;
  }
}

Future<void> _tapScrollable(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 80, scrollable: find.byType(Scrollable).first);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Widget _staffCreateHarness({
  required Widget child,
  AuthSessionNotifier? authNotifier,
  ProvisioningNotifier? provisioningNotifier,
  List<BranchSummary>? assignableBranches,
  bool branchLoadFails = false,
}) {
  return ProviderScope(
    overrides: [
      startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
      authSessionProvider.overrideWith(() => authNotifier ?? _OwnerAuthNotifier()),
      if (provisioningNotifier != null) provisioningNotifierProvider.overrideWith(() => provisioningNotifier),
      staffAssignableBranchesProvider.overrideWith((ref) async {
        if (branchLoadFails) {
          throw StateError('offline');
        }
        return assignableBranches ?? const [_testBranch];
      }),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: AppRoutes.staffCreate, builder: (context, state) => child),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
        ],
        initialLocation: AppRoutes.staffCreate,
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

  group('StaffCreatePage', () {
    testWidgets('renders form fields for owner', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage()));
      await tester.pumpAndSettle();

      expect(find.text('Create staff account'), findsWidgets);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Initial password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create staff account'), findsOneWidget);
    });

    testWidgets('branch assignments show name not raw id', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage()));
      await tester.pumpAndSettle();

      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('Branch branch-test-uuid'), findsNothing);
      expect(find.textContaining('branch-test-uuid'), findsNothing);
    });

    testWidgets('branch info icon tooltip carries full branch details', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage()));
      await tester.pumpAndSettle();

      final branchTooltipFinder = find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.byWidgetPredicate((widget) => widget is Tooltip && widget.message == _testBranch.detailTooltip),
      );
      expect(branchTooltipFinder, findsOneWidget);
      expect(find.descendant(of: branchTooltipFinder, matching: find.byIcon(Icons.info_outline)), findsOneWidget);
    });

    testWidgets('missing branch row falls back to branch id label', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), assignableBranches: const []));
      await tester.pumpAndSettle();

      expect(find.text('Branch branch-test-uuid'), findsOneWidget);
      expect(find.text('Main Branch'), findsNothing);
    });

    testWidgets('branch fetch error shows warning and id fallback', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), branchLoadFails: true));
      await tester.pumpAndSettle();

      expect(find.text('Branch branch-test-uuid'), findsOneWidget);
      expect(find.textContaining('Could not load branch details'), findsOneWidget);
    });

    testWidgets('doctor sees permission denied message', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), authNotifier: _DoctorAuthNotifier()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only clinic owners and administrators'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create staff account'), findsNothing);
    });

    testWidgets('bootstrap admin sees owner role when no owner exists', (tester) async {
      final provisioning = _TestProvisioningNotifier(ownerAlreadyExists: false);

      await tester.pumpWidget(
        _staffCreateHarness(
          child: const StaffCreatePage(),
          authNotifier: _BootstrapAuthNotifier(),
          provisioningNotifier: provisioning,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();

      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('administrator without owner inference hides owner role', (tester) async {
      final provisioning = _TestProvisioningNotifier(ownerAlreadyExists: true);

      await tester.pumpWidget(
        _staffCreateHarness(
          child: const StaffCreatePage(),
          authNotifier: _AdministratorAuthNotifier(),
          provisioningNotifier: provisioning,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();

      expect(find.text('Owner'), findsNothing);
      expect(find.text('Receptionist'), findsOneWidget);
    });

    testWidgets('empty username shows validation without RPC', (tester) async {
      final provisioning = _TestProvisioningNotifier();

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(provisioning.createCalls, 0);
      expect(find.text('Username is required.'), findsOneWidget);
    });

    testWidgets('invalid username format blocked client-side', (tester) async {
      final provisioning = _TestProvisioningNotifier();

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'ab');
      await tester.enterText(find.byType(TextFormField).at(1), 'Jane Doe');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret12');
      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(provisioning.createCalls, 0);
      expect(find.text('Username must be 3–32 characters.'), findsOneWidget);
    });

    testWidgets('password shorter than six characters rejected', (tester) async {
      final provisioning = _TestProvisioningNotifier();

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'newstaff');
      await tester.enterText(find.byType(TextFormField).at(1), 'Jane Doe');
      await tester.enterText(find.byType(TextFormField).at(2), '12345');
      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(provisioning.createCalls, 0);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('successful create shows credentials dialog', (tester) async {
      final provisioning = _TestProvisioningNotifier();

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'reception');
      await tester.enterText(find.byType(TextFormField).at(1), 'Front Desk');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret12');
      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receptionist').last);
      await tester.pumpAndSettle();
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(provisioning.createCalls, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Staff account created'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('reception')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('secret12')), findsOneWidget);
    });

    testWidgets('RPC owner denial shows error banner', (tester) async {
      final provisioning = _TestProvisioningNotifier(failCreate: true, ownerAlreadyExists: true);

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'owner2');
      await tester.enterText(find.byType(TextFormField).at(1), 'Second Owner');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret12');
      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Owner').last);
      await tester.pumpAndSettle();
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(find.textContaining('Only existing owners'), findsOneWidget);
    });

    testWidgets('dismiss error banner clears message', (tester) async {
      final provisioning = _TestProvisioningNotifier(
        initialState: const ProvisioningUiState(errorMessage: 'A staff account with this username already exists.'),
      );

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already exists'), findsNothing);
    });

    testWidgets('home action navigates away', (tester) async {
      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('stupid usage: spaces-only full name blocked by form validator', (tester) async {
      final provisioning = _TestProvisioningNotifier();

      await tester.pumpWidget(_staffCreateHarness(child: const StaffCreatePage(), provisioningNotifier: provisioning));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'newuser');
      await tester.enterText(find.byType(TextFormField).at(1), '     ');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret12');
      await _tapScrollable(tester, find.widgetWithText(FilledButton, 'Create staff account'));

      expect(provisioning.createCalls, 0);
      expect(find.text('Full name is required'), findsOneWidget);
    });
  });
}
