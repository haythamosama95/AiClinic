// Test-only harness for patient page widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/active_branch_name_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../helpers/role_permission_seed.dart';

const patientsTestPatientId = '11111111-1111-4111-8111-111111111111';
const patientsWideSurfaceSize = Size(1400, 1000);

/// Records matched route locations during [createPatientsTestRouter] navigation.
class PatientsTestNavigationLog {
  final visitedLocations = <String>[];

  void record(GoRouterState state) {
    visitedLocations.add(state.uri.toString());
  }
}

/// Router plus navigation log returned by [pumpPatientsRouter].
class PatientsTestRouterBundle {
  const PatientsTestRouterBundle({
    required this.router,
    required this.navigationLog,
  });

  final GoRouter router;
  final PatientsTestNavigationLog navigationLog;
}

/// Tracks [PatientListNotifier.reload] and [PatientListNotifier.applyFilters].
class SpyPatientListNotifier extends PatientListNotifier {
  SpyPatientListNotifier(this._state);

  final PatientListUiState _state;

  var reloadCallCount = 0;
  var applyFiltersCallCount = 0;
  PatientListFilters? lastAppliedFilters;

  @override
  Future<PatientListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    return _state;
  }

  @override
  Future<void> reload() async {
    reloadCallCount++;
    state = AsyncData(_state);
  }

  @override
  Future<void> applyFilters(PatientListFilters filters) async {
    applyFiltersCallCount++;
    lastAppliedFilters = filters;
  }
}

/// Never completes so [patientListProvider] stays in loading.
class LoadingPatientListNotifier extends PatientListNotifier {
  @override
  Future<PatientListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    return Completer<PatientListUiState>().future;
  }

  @override
  Future<void> applyFilters(PatientListFilters filters) async {
    // No-op: PatientsPage applies default filters during build; loading data here
    // would overwrite the loading state the test is asserting.
  }

  @override
  Future<void> reload() async {
    // No-op: keep the provider in loading for skeleton assertions.
  }
}

/// Throws on build to surface the list error state.
class ErrorPatientListNotifier extends PatientListNotifier {
  ErrorPatientListNotifier(this.message);

  final String message;

  @override
  Future<PatientListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    throw Exception(message);
  }

  @override
  Future<void> reload() async {
    state = AsyncError<PatientListUiState>(Exception(message), StackTrace.current);
  }

  @override
  Future<void> applyFilters(PatientListFilters filters) async {
    // No-op: PatientsPage applies default filters during build; loading data here
    // would overwrite the error state the test is asserting.
  }
}

/// Authenticated session for patient widget tests.
AuthSessionState patientsAuthSession({
  Set<String>? permissions,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final branches = branchIds ?? [testBranchAId];
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? RolePermissionSeed.administrator,
      branchIds: branches,
      activeBranchId: activeBranchId ?? branches.first,
    ),
  );
}

/// Grants [PermissionKeys.patientsReassignMrn] on top of [base] (administrator by default).
Set<String> patientsWithReassignMrnPermission([Set<String>? base]) {
  return {
    ...(base ?? RolePermissionSeed.administrator),
    PermissionKeys.patientsReassignMrn,
  };
}

/// Builds a [PatientListUiState] from [items] for [SpyPatientListNotifier].
PatientListUiState buildPatientListState({
  List<PatientListItem>? items,
  int? totalCount,
  PatientListFilters filters = const PatientListFilters(pageSize: 10),
  String? searchHint,
}) {
  final resolvedItems = items ?? samplePatientList();
  return PatientListUiState(
    rows: PatientTableRow.fromItems(resolvedItems),
    totalCount: totalCount ?? resolvedItems.length,
    filters: filters,
    searchHint: searchHint,
  );
}

List<Override> _resolvePatientsOverrides({
  Set<String>? permissions,
  required List<Override> overrides,
}) {
  if (overrides.isNotEmpty) {
    return overrides;
  }
  return patientsProviderOverrides(
    auth: permissions != null ? patientsAuthSession(permissions: permissions) : null,
  );
}

/// Default provider bundle for patient list, detail, and dialog widget tests.
List<Override> patientsProviderOverrides({
  AuthSessionState? auth,
  FakePatientRepository? patientRepo,
  SpyPatientListNotifier? listNotifier,
  Override? patientListOverride,
  String? patientId,
  PatientDetail? patientDetail,
  Object? detailError,
  List<VisitListItem>? pastVisits,
  List<AppointmentListItem>? upcomingAppointments,
  String? upcomingAppointmentsBranchId,
  List<PatientVisitDocument>? visitDocuments,
  InvoiceListPageResult? patientInvoices,
  String? activeBranchName,
  bool customPatientDetail = false,
  bool customPatientInvoices = false,
  bool customPatientVisitDocuments = false,
  bool customPatientPastVisits = false,
  List<Override> extraOverrides = const [],
}) {
  final resolvedAuth = auth ?? patientsAuthSession();
  final resolvedDetail = patientDetail ??
      (patientId != null ? samplePatientDetail(id: patientId) : null);
  final repo = patientRepo ??
      FakePatientRepository(
        patients: samplePatientList(),
        detail: resolvedDetail,
      );

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(resolvedAuth),
    ),
    permissionServiceProvider.overrideWith(
      (ref) => PermissionService(ref.watch(authSessionProvider).context),
    ),
    patientRepositoryProvider.overrideWith((ref) => repo),
    activeBranchNameProvider.overrideWith(
      (ref) async => activeBranchName ?? 'Branch A',
    ),
    if (patientListOverride != null)
      patientListOverride
    else
      patientListProvider.overrideWith(
        () => listNotifier ?? SpyPatientListNotifier(buildPatientListState()),
      ),
    if (patientId != null && !customPatientDetail)
      if (detailError != null)
        patientDetailProvider(patientId).overrideWith(
          (ref) async => throw detailError,
        )
      else
        patientDetailProvider(patientId).overrideWith(
          (ref) async => resolvedDetail ?? samplePatientDetail(id: patientId),
        ),
    if (patientId != null && !customPatientPastVisits)
      patientPastVisitsProvider(patientId).overrideWith(
        (ref) async => pastVisits ?? const [],
      ),
    if (patientId != null)
      patientUpcomingAppointmentsProvider(
        PatientDetailHistoryQuery(
          patientId: patientId,
          branchId: upcomingAppointmentsBranchId ??
              resolvedDetail?.branchId ??
              testBranchAId,
        ),
      ).overrideWith(
        (ref) async => upcomingAppointments ?? const [],
      ),
    if (patientId != null && !customPatientVisitDocuments)
      patientVisitDocumentsProvider(patientId).overrideWith(
        (ref) async => visitDocuments ?? const [],
      ),
    if (patientId != null && !customPatientInvoices)
      patientInvoicesProvider(patientId).overrideWith(
        (ref) async =>
            patientInvoices ?? const InvoiceListPageResult(items: [], hasMore: false),
      ),
    ...extraOverrides,
  ];
}

/// GoRouter with stub destination markers for patient navigation assertions.
GoRouter createPatientsTestRouter({
  required Widget home,
  PatientsTestNavigationLog? navigationLog,
  String initialLocation = AppRoutes.patients,
  List<RouteBase> extraRoutes = const [],
  Widget Function(BuildContext context, GoRouterState state)? patientDetailBuilder,
  Widget Function(BuildContext context, GoRouterState state)? billingInvoiceDetailBuilder,
}) {
  final log = navigationLog ?? PatientsTestNavigationLog();

  Widget marker(String label) => Scaffold(
        key: Key('route_$label'),
        body: Center(child: Text('stub:$label')),
      );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.patients,
        builder: (context, state) {
          log.record(state);
          return home;
        },
      ),
      GoRoute(
        path: '${AppRoutes.patients}/:patientId',
        builder: patientDetailBuilder ??
            (context, state) {
              log.record(state);
              return marker('patient-${state.pathParameters['patientId']}');
            },
      ),
      GoRoute(
        path: '${AppRoutes.billingInvoices}/:invoiceId',
        builder: billingInvoiceDetailBuilder ??
            (context, state) {
              log.record(state);
              return marker('invoice-detail-${state.pathParameters['invoiceId']}');
            },
      ),
      ...extraRoutes,
    ],
  );
}

/// Pumps [child] inside the canonical patients widget-test shell.
Future<void> pumpPatientsSurface(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = patientsWideSurfaceSize,
  Set<String>? permissions,
  bool wrapToastHost = true,
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final appChild = wrapToastHost
      ? AppToastHost(
          child: Scaffold(
            body: SizedBox(
              width: surfaceSize.width,
              height: surfaceSize.height,
              child: child,
            ),
          ),
        )
      : Scaffold(
          body: SizedBox(
            width: surfaceSize.width,
            height: surfaceSize.height,
            child: child,
          ),
        );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _resolvePatientsOverrides(
        permissions: permissions,
        overrides: overrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: appChild,
      ),
    ),
  );
}

/// Pumps [home] behind a patients [GoRouter] with stub route markers.
Future<PatientsTestRouterBundle> pumpPatientsRouter(
  WidgetTester tester, {
  required Widget home,
  PatientsTestNavigationLog? navigationLog,
  String initialLocation = AppRoutes.patients,
  List<Override> overrides = const [],
  Size surfaceSize = patientsWideSurfaceSize,
  Set<String>? permissions,
  List<RouteBase> extraRoutes = const [],
  Widget Function(BuildContext context, GoRouterState state)? patientDetailBuilder,
  Widget Function(BuildContext context, GoRouterState state)? billingInvoiceDetailBuilder,
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final log = navigationLog ?? PatientsTestNavigationLog();
  final router = createPatientsTestRouter(
    home: home,
    navigationLog: log,
    initialLocation: initialLocation,
    extraRoutes: extraRoutes,
    patientDetailBuilder: patientDetailBuilder,
    billingInvoiceDetailBuilder: billingInvoiceDetailBuilder,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _resolvePatientsOverrides(
        permissions: permissions,
        overrides: overrides,
      ),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );

  return PatientsTestRouterBundle(router: router, navigationLog: log);
}

/// Minimal Material shell for patient dialog widget tests (includes [AppToastHost]).
Future<void> pumpPatientsDialogShell(
  WidgetTester tester, {
  required Widget home,
  List<Override> overrides = const [],
  Set<String>? permissions,
  Size surfaceSize = const Size(800, 700),
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: _resolvePatientsOverrides(
        permissions: permissions,
        overrides: overrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            AppToastHost(child: child ?? const SizedBox.shrink()),
        home: Scaffold(body: home),
      ),
    ),
  );
}

/// Reads the active [ProviderContainer] for the patients test shell.
///
/// Do not keep the returned container across a second [pumpWidget] — holding the
/// reference prevents Riverpod from disposing the old scope and breaks re-pumps.
ProviderContainer patientsProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(
      find.descendant(
        of: find.byType(MaterialApp),
        matching: find.byType(Scaffold),
      ),
    ),
  );
}

/// Pumps one frame plus a short settle delay for patient async providers.
Future<void> pumpPatientsFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
