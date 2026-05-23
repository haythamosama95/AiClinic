import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_edit_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_list_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_registration_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/patient_rpc_test_client.dart';

const _branchId = '44444444-4444-4444-8444-444444444444';
const _branch = BranchSummary(id: _branchId, name: 'Main');
const _patientId = '11111111-1111-4111-8111-111111111111';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

Widget _scope({
  required Widget child,
  Set<String> permissions = RolePermissionSeed.labStaff,
  PatientRpcTestClient? client,
}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: StaffRole.labStaff,
              permissions: permissions,
              activeBranchId: _branchId,
            ),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => PatientRepository(client ?? PatientRpcTestClient())),
      patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
      staffAssignableBranchesProvider.overrideWith((ref) async => [_branch]),
    ],
    child: child,
  );
}

void main() {
  group('lab_staff view-only permission guards', () {
    testWidgets('trivial: shell shows Patients but not register shortcut', (tester) async {
      await _pump(tester, _scope(child: const MaterialApp(home: AuthShellPage())));

      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Register patient'), findsNothing);
    });

    testWidgets('trivial: list and search allowed without create FAB', (tester) async {
      await _pump(tester, _scope(child: const MaterialApp(home: PatientListPage())));

      expect(find.byKey(const Key('patient_list_table')), findsOneWidget);
      expect(find.byKey(const Key('patient_search_field')), findsOneWidget);
      expect(find.byKey(const Key('patient_list_register_fab')), findsNothing);
      expect(find.byKey(const Key('patient_list_empty_register')), findsNothing);
    });

    testWidgets('advanced: can open detail and visits placeholder', (tester) async {
      await _pump(
        tester,
        _scope(
          child: MaterialApp(home: PatientDetailPage(patientId: _patientId)),
        ),
      );

      expect(find.byKey(const Key('patient_detail_profile')), findsOneWidget);
      expect(find.byKey(const Key('patient_visits_placeholder')), findsOneWidget);
      expect(find.byKey(const Key('patient_detail_edit')), findsNothing);
      expect(find.byKey(const Key('patient_detail_archive')), findsNothing);
    });

    testWidgets('stupid usage: direct register route shows permission denied', (tester) async {
      await _pump(tester, _scope(child: const MaterialApp(home: PatientRegistrationPage())));

      expect(find.text('You do not have permission to register patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_register_submit')), findsNothing);
    });

    testWidgets('stupid usage: direct edit route shows permission denied', (tester) async {
      await _pump(
        tester,
        _scope(
          child: MaterialApp(home: PatientEditPage(patientId: _patientId)),
        ),
      );

      expect(find.byKey(const Key('patient_edit_permission_denied')), findsOneWidget);
      expect(find.byKey(const Key('patient_edit_submit')), findsNothing);
    });

    testWidgets('edge case: list row opens detail but no edit/archive actions', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientListPage()),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
        ],
        initialLocation: AppRoutes.patients,
      );

      await _pump(tester, _scope(child: MaterialApp.router(routerConfig: router)));

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_detail_edit')), findsNothing);
      expect(find.byKey(const Key('patient_detail_archive')), findsNothing);
    });

    testWidgets('regression: user without patients.view sees denial on list', (tester) async {
      await _pump(
        tester,
        _scope(
          permissions: const {PermissionKeys.aiAccess},
          child: const MaterialApp(home: PatientListPage()),
        ),
      );

      expect(find.text('You do not have permission to view patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_list_table')), findsNothing);
    });
  });

  group('doctor view-only (spec case 10)', () {
    testWidgets('list/detail allowed; create/edit/archive denied in UI', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientListPage()),
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => const PatientRegistrationPage()),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
        ],
        initialLocation: AppRoutes.patients,
      );

      await _pump(
        tester,
        _scope(
          permissions: const {PermissionKeys.patientsView},
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      expect(find.byKey(const Key('patient_list_table')), findsOneWidget);
      expect(find.byKey(const Key('patient_list_register_fab')), findsNothing);

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_detail_edit')), findsNothing);
      expect(find.byKey(const Key('patient_detail_archive')), findsNothing);
    });
  });
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
