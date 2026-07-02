import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/visit_rpc_test_client.dart';
import 'visit_encounter_test_support.dart';

const _originalPlan = 'Rest and hydration';
const _updatedPlan = 'Rest, hydration, and follow-up in one week';

void _noop() {}

VisitDetail _completedVisit({String plan = _originalPlan}) {
  return sampleEncounterVisit().copyWith(
    status: VisitStatus.completed,
    documentation: VisitClinicalNote(
      complaint: 'Headache',
      history: 'Two days',
      examination: 'Normal exam',
      diagnosis: 'Tension headache',
      plan: plan,
      updatedAt: DateTime.utc(2026, 5, 31, 10),
    ),
  );
}

VisitDocumentationState _completedViewingDocState({String plan = _originalPlan}) {
  final visit = _completedVisit(plan: plan);
  return VisitDocumentationState.fromVisit(visit);
}

VisitDocumentationState _completedEditingFieldViewDocState({String plan = _originalPlan}) {
  return _completedViewingDocState(plan: plan).copyWith(
    workspaceEditMode: WorkspaceEditMode.editing,
    noteEditMode: DocumentationEditMode.readOnly,
  );
}

List<Override> _completedVisitOverrides({
  required VisitDocumentationState docState,
  required _CompletedVisitRpcClient client,
}) {
  return [
    authSessionProvider.overrideWith(
      () => _PresetAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            branchIds: [encounterTestBranchId],
            activeBranchId: encounterTestBranchId,
            permissions: {PermissionKeys.visitsEditSoap, PermissionKeys.visitsUploadAttachment},
          ),
        ),
      ),
    ),
    visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
    visitDocumentationProvider(
      encounterTestVisitId,
    ).overrideWith(() => _SeededVisitDocumentationNotifier(docState)),
    patientDetailProvider(
      encounterTestPatientId,
    ).overrideWith((ref) async => samplePatientDetail(id: encounterTestPatientId)),
    patientSafetyProvider(encounterTestPatientId).overrideWith(() => _EmptyPatientSafetyNotifier()),
  ];
}

Future<void> pumpCompletedVisitWidget(
  WidgetTester tester, {
  required Widget child,
  required VisitDocumentationState docState,
  required _CompletedVisitRpcClient client,
  Size size = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: _completedVisitOverrides(docState: docState, client: client),
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        home: Scaffold(body: SizedBox(width: size.width, height: size.height, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpCompletedVisitDocumentationPage(
  WidgetTester tester, {
  required VisitDocumentationState docState,
  required _CompletedVisitRpcClient client,
  bool startInEditMode = false,
  GoRouter? router,
  Size size = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final resolvedRouter =
      router ??
      GoRouter(
        initialLocation: AppRoutes.visitDocument(encounterTestVisitId, startEditing: startInEditMode),
        routes: [
          GoRoute(
            path: AppRoutes.visitDetail(encounterTestVisitId),
            builder: (_, _) => const Scaffold(key: Key('visit_detail_landing')),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (_, state) {
              final edit = state.uri.queryParameters['edit'] == '1';
              return VisitDocumentationPage(
                visitId: state.pathParameters['visitId'],
                startInEditMode: edit,
              );
            },
          ),
        ],
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _completedVisitOverrides(docState: docState, client: client),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        routerConfig: resolvedRouter,
      ),
    ),
  );

  if (startInEditMode) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

ProviderContainer _containerFromWorkspace(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
}

ProviderContainer _containerFromPlanPhase(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_phase_plan'))));
}

Future<void> _openPlanPhase(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('encounter_step_plan')));
  await tester.pumpAndSettle();
}

/// Rebuilds [EncounterPhasePlan] from live documentation state so edit/save toggles reflect notifier updates.
class _CompletedVisitPlanPhaseHarness extends ConsumerWidget {
  const _CompletedVisitPlanPhaseHarness({required this.canEdit, required this.onRefresh});

  final bool canEdit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitDocumentationProvider(encounterTestVisitId)).value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    return EncounterPhasePlan(
      visitId: encounterTestVisitId,
      state: state,
      canEdit: canEdit,
      canUploadAttachments: true,
      onRefresh: onRefresh,
    );
  }
}

void main() {
  group('FE-009 — Field card edit toggle', () {
    late _CompletedVisitRpcClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = _CompletedVisitRpcClient();
    });

    testWidgets('treatment notes card toggles view → edit → view after save', (tester) async {
      final docState = _completedEditingFieldViewDocState();

      await pumpCompletedVisitWidget(
        tester,
        docState: docState,
        client: client,
        child: const _CompletedVisitPlanPhaseHarness(canEdit: true, onRefresh: _noop),
      );

      expect(find.text(_originalPlan), findsOneWidget);
      expect(find.byKey(const Key('clinical_note_edit_button')), findsOneWidget);
      expect(find.byKey(const Key('clinical_note_save_button')), findsNothing);

      await tester.tap(find.byKey(const Key('clinical_note_edit_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clinical_note_save_button')), findsOneWidget);
      expect(find.byKey(const Key('clinical_note_edit_button')), findsNothing);

      final container = _containerFromPlanPhase(tester);
      container.read(visitDocumentationProvider(encounterTestVisitId).notifier).updatePlan(_updatedPlan);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clinical_note_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clinical_note_edit_button')), findsOneWidget);
      expect(find.byKey(const Key('clinical_note_save_button')), findsNothing);
      expect(find.text(_updatedPlan), findsOneWidget);

      expect(
        container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.noteEditMode,
        DocumentationEditMode.readOnly,
      );
      expect(client.rpcCalls.where((call) => call.fn == 'save_visit_documentation'), hasLength(1));
      expect(client.lastSavedPlan, _updatedPlan);
    });
  });

  group('E2E-003 — Completed visit edit workflow (widget-level)', () {
    late _CompletedVisitRpcClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = _CompletedVisitRpcClient();
    });

    testWidgets('Edit visit button enters workspace edit mode', (tester) async {
      final docState = _completedViewingDocState();

      await pumpCompletedVisitDocumentationPage(
        tester,
        docState: docState,
        client: client,
      );

      expect(find.byKey(const Key('visit_edit_workspace_button')), findsOneWidget);
      expect(find.byKey(const Key('visit_save_close_button')), findsNothing);

      await tester.tap(find.byKey(const Key('visit_edit_workspace_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_edit_workspace_button')), findsNothing);
      expect(find.byKey(const Key('visit_save_close_button')), findsOneWidget);

      final container = _containerFromWorkspace(tester);
      expect(
        container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.workspaceEditMode,
        WorkspaceEditMode.editing,
      );
      expect(
        container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.visit.status,
        VisitStatus.completed,
      );
    });

    testWidgets('startInEditMode enters workspace edit mode on load', (tester) async {
      final docState = _completedViewingDocState();

      await pumpCompletedVisitDocumentationPage(
        tester,
        docState: docState,
        client: client,
        startInEditMode: true,
      );

      expect(find.byKey(const Key('visit_edit_workspace_button')), findsNothing);
      expect(find.byKey(const Key('visit_save_close_button')), findsOneWidget);

      final container = _containerFromWorkspace(tester);
      expect(
        container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.workspaceEditMode,
        WorkspaceEditMode.editing,
      );
    });

    testWidgets('modify plan and Save & close persists while status stays completed', (tester) async {
      final docState = _completedEditingFieldViewDocState();

      await pumpCompletedVisitDocumentationPage(
        tester,
        docState: docState,
        client: client,
      );

      final container = _containerFromWorkspace(tester);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.updatePlan(_updatedPlan);
      await tester.pumpAndSettle();

      expect(
        container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.hasUnsavedChanges,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('visit_save_close_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_detail_landing')), findsOneWidget);
      expect(client.rpcCalls.where((call) => call.fn == 'save_visit_documentation'), hasLength(1));
      expect(client.lastSavedPlan, _updatedPlan);

      final reloadedVisit = VisitDetail.fromRow(client.lastGetVisitDetail!);
      expect(reloadedVisit, isNotNull);
      expect(reloadedVisit!.status, VisitStatus.completed);
      expect(reloadedVisit.documentation?.plan, _updatedPlan);
    });
  });
}

/// Tracks saved documentation and returns completed visit payloads from [get_visit].
class _CompletedVisitRpcClient extends VisitRpcTestClient {
  String persistedPlan = _originalPlan;
  String? lastSavedPlan;
  Map<String, dynamic>? lastGetVisitDetail;

  Map<String, dynamic> _visitPayload(String visitId) {
    return {
      'id': visitId,
      'branch_id': encounterTestBranchId,
      'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': encounterTestPatientId,
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Test',
      'visit_date': '2026-05-31',
      'status': 'completed',
      'updated_at': '2026-05-31T10:05:00.000Z',
      'documentation': {
        'complaint': 'Headache',
        'history': 'Two days',
        'examination': 'Normal exam',
        'diagnosis': 'Tension headache',
        'plan': persistedPlan,
        'updated_at': '2026-05-31T10:05:00.000Z',
      },
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'save_visit_documentation') {
      lastSavedPlan = params?['p_plan'] as String?;
      if (lastSavedPlan != null) {
        persistedPlan = lastSavedPlan!;
      }
      rpcResults['save_visit_documentation'] = {
        'success': true,
        'data': {
          'visit_id': params?['p_visit_id'] ?? encounterTestVisitId,
          'updated_at': '2026-05-31T10:05:00.000Z',
        },
      };
    }
    if (fn == 'get_visit') {
      final visitId = params?['p_visit_id']?.toString() ?? encounterTestVisitId;
      lastGetVisitDetail = _visitPayload(visitId);
      rpcResults['get_visit'] = {'success': true, 'data': lastGetVisitDetail};
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _SeededVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SeededVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _EmptyPatientSafetyNotifier extends PatientSafetyNotifier {
  _EmptyPatientSafetyNotifier() : super(encounterTestPatientId);

  @override
  Future<PatientSafetyContext> build() async => const PatientSafetyContext();
}
