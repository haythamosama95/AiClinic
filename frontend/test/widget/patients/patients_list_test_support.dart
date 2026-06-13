import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patients_page.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';

const defaultClinicBranches = [
  BranchListItem(id: testBranchAId, name: 'Branch A', code: 'A1', isActive: true),
  BranchListItem(id: testBranchBId, name: 'Branch B', code: 'B1', isActive: true),
];

/// Pumps [PatientsPage] at desktop list size.
Future<void> pumpPatientsPage(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> enterPatientSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> openPatientsFilterSidebar(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list_outlined));
  await tester.pumpAndSettle();
}

Future<void> openPatientsSortPopover(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.sort_outlined));
  await tester.pumpAndSettle();
}

Future<void> applyPatientsFilters(WidgetTester tester) async {
  await tester.tap(find.text('Apply Filters'));
  await tester.pumpAndSettle();
}

Future<void> clearPatientsFilters(WidgetTester tester) async {
  await tester.tap(find.text('Clear All'));
  await tester.pumpAndSettle();
}

AppIconButton patientsPaginationButton(WidgetTester tester, String tooltip) {
  return tester.widget<AppIconButton>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(AppIconButton)));
}

Future<void> selectBranchFilterOption(WidgetTester tester, String optionLabel) async {
  await tester.tap(find.descendant(of: find.byType(AppFilterSelect<String>), matching: find.byType(EditableText)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> selectLastVisitFilterOption(WidgetTester tester, String optionLabel) async {
  await tester.tap(
    find.descendant(of: find.byType(AppFilterSelect<PatientLastVisitFilter>), matching: find.byType(EditableText)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> tapPatientRow(WidgetTester tester, String patientName) async {
  await tester.tap(find.text(patientName));
  await tester.pumpAndSettle();
}

Future<void> tapBackToPatientsList(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back to patients'));
  await tester.pumpAndSettle();
}

Widget patientsListHost({
  FakePatientRepository? repository,
  List<PatientListItem>? patients,
  Set<String> permissions = const {'patients.view', 'patients.create'},
  List<String> branchIds = const [testBranchAId, testBranchBId],
  String? activeBranchId,
  List<BranchListItem>? clinicBranches,
  TestAuthSessionNotifier? authNotifier,
  ThemeData? theme,
}) {
  final repo = repository ?? FakePatientRepository(patients: patients ?? const []);
  final auth = authNotifier ?? _PresetAuthSessionNotifier(_authState(permissions, branchIds, activeBranchId));

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => auth),
      patientRepositoryProvider.overrideWith((ref) => repo),
      clinicSetupBranchesProvider.overrideWith((ref) async => clinicBranches ?? defaultClinicBranches),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: PatientsPage()),
    ),
  );
}

AuthSessionState _authState(Set<String> permissions, List<String> branchIds, String? activeBranchId) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions,
      branchIds: branchIds,
      activeBranchId: activeBranchId ?? branchIds.first,
    ),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class SwitchablePatientsListAuthNotifier extends TestAuthSessionNotifier {
  SwitchablePatientsListAuthNotifier(AuthSessionState session) : _session = session;

  AuthSessionState _session;

  @override
  AuthSessionState build() => _session;

  @override
  void setActiveBranch(String branchId) {
    final context = _session.context;
    if (context == null) {
      return;
    }
    _session = _session.copyWith(context: context.copyWith(activeBranchId: branchId));
    state = _session;
  }
}

/// Router with patients list and detail routes for create/delete navigation tests.
GoRouter patientsListTestRouter({String initialLocation = AppRoutes.patients}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.patients,
        builder: (context, state) => const Scaffold(body: PatientsPage()),
      ),
      GoRoute(
        path: '${AppRoutes.patients}/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          return Scaffold(body: PatientDetailPage(patientId: patientId));
        },
      ),
    ],
  );
}

Widget patientsListRouterHost({
  FakePatientRepository? repository,
  List<PatientListItem>? patients,
  Set<String> permissions = const {'patients.view', 'patients.create', 'patients.edit', 'patients.delete'},
  List<String> branchIds = const [testBranchAId, testBranchBId],
  String? activeBranchId,
  List<BranchListItem>? clinicBranches,
  GoRouter? router,
  ThemeData? theme,
}) {
  final repo = repository ?? FakePatientRepository(patients: patients ?? const []);
  final auth = _PresetAuthSessionNotifier(_authState(permissions, branchIds, activeBranchId));

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => auth),
      patientRepositoryProvider.overrideWith((ref) => repo),
      clinicSetupBranchesProvider.overrideWith((ref) async => clinicBranches ?? defaultClinicBranches),
    ],
    child: MaterialApp.router(
      theme: theme ?? AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      routerConfig: router ?? patientsListTestRouter(),
    ),
  );
}
