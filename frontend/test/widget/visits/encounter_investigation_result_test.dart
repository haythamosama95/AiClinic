import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_result_capture_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/visit_rpc_test_client.dart';
import 'visit_encounter_test_support.dart';

const _priorVisitId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _priorInvestigationLineId = 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii';

VisitInvestigation _priorPendingInvestigation() {
  return VisitInvestigation(
    id: _priorInvestigationLineId,
    name: 'CBC',
    note: 'Fasting required',
    orderedVisitId: _priorVisitId,
    orderedVisitDate: DateTime.utc(2026, 5, 15),
  );
}

VisitDocumentationState _docStateWithPriorPendingInvestigation() {
  final visit = sampleEncounterVisit().copyWith(pendingInvestigations: [_priorPendingInvestigation()]);
  return sampleEncounterDocState(visit: visit);
}

Future<void> _pumpInvestigationResultWidget(
  WidgetTester tester, {
  required Widget child,
  required VisitDocumentationState docState,
  VisitRpcTestClient? rpcClient,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final overrides = <Override>[
    authSessionProvider.overrideWith(
      () => _PresetAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            branchIds: [encounterTestBranchId],
            activeBranchId: encounterTestBranchId,
            permissions: {PermissionKeys.visitsEditSoap, PermissionKeys.visitsCreate},
          ),
        ),
      ),
    ),
    patientDetailProvider(
      encounterTestPatientId,
    ).overrideWith((ref) async => samplePatientDetail(id: encounterTestPatientId)),
    patientSafetyProvider(encounterTestPatientId).overrideWith(() => _EmptyPatientSafetyNotifier()),
    visitDocumentationProvider(
      encounterTestVisitId,
    ).overrideWith(() => _SeededVisitDocumentationNotifier(docState)),
  ];

  if (rpcClient != null) {
    overrides.add(visitRepositoryProvider.overrideWith((ref) => VisitRepository(rpcClient)));
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await container.read(visitDocumentationProvider(encounterTestVisitId).future);
}

Future<void> _recordResultOnPendingInvestigation(WidgetTester tester, {required String result}) async {
  await tester.tap(find.byKey(Key('investigation_result_record_$_priorInvestigationLineId')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.byKey(Key('investigation_result_form_$_priorInvestigationLineId')), findsOneWidget);

  final resultField = find.descendant(
    of: find.byKey(Key('investigation_result_form_$_priorInvestigationLineId')),
    matching: find.byType(TextField),
  );
  await tester.tap(resultField);
  await tester.pump();
  await tester.enterText(resultField, result);
  await tester.pump();

  final saveButton = find.byKey(Key('investigation_result_save_$_priorInvestigationLineId'));
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('EDGE-006 — Investigation result on prior-visit pending order', () {
    testWidgets('shows pending investigation from prior visit with record action', (tester) async {
      await pumpEncounterWidget(
        tester,
        docState: _docStateWithPriorPendingInvestigation(),
        child: InvestigationResultCaptureList(
          pendingInvestigations: [_priorPendingInvestigation()],
          canEdit: true,
          visitId: encounterTestVisitId,
          deferPersistence: true,
          onChanged: () {},
        ),
      );

      expect(find.text('Investigation results'), findsOneWidget);
      expect(find.byKey(Key('pending_investigation_$_priorInvestigationLineId')), findsOneWidget);
      expect(find.text('CBC'), findsOneWidget);
      expect(find.text('Fasting required'), findsOneWidget);
      expect(find.textContaining('Ordered May 15, 2026'), findsOneWidget);
      expect(find.byKey(Key('investigation_result_record_$_priorInvestigationLineId')), findsOneWidget);
    });

    testWidgets('stages result on correct investigation and removes it from pending list after refresh', (tester) async {
      const resultText = 'Within normal limits';
      final docState = _docStateWithPriorPendingInvestigation();

      await _pumpInvestigationResultWidget(
        tester,
        docState: docState,
        child: const _DeferPersistenceHarness(),
      );

      await _recordResultOnPendingInvestigation(tester, result: resultText);
      await tester.pump();

      expect(find.byKey(const Key('investigation_results_resolved')), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('investigation_results_resolved'))),
      );
      final nextState = container.read(visitDocumentationProvider(encounterTestVisitId).notifier).state.requireValue;

      expect(nextState.encounterDraft.investigationResults[_priorInvestigationLineId], resultText);
      expect(
        nextState.visit.pendingInvestigations.single,
        isA<VisitInvestigation>()
            .having((investigation) => investigation.id, 'id', _priorInvestigationLineId)
            .having((investigation) => investigation.result, 'result', resultText)
            .having((investigation) => investigation.hasResult, 'hasResult', isTrue),
      );
      expect(find.byKey(const Key('investigation_results_resolved')), findsOneWidget);
      expect(find.byKey(Key('pending_investigation_$_priorInvestigationLineId')), findsNothing);
    });

    testWidgets('records result immediately via repository when persistence is not deferred', (tester) async {
      const resultText = 'Elevated WBC';
      final client = VisitRpcTestClient(
        rpcResults: {
          'record_investigation_result': {
            'success': true,
            'data': {'result_recorded_at': '2026-06-01T09:00:00.000Z'},
          },
        },
      );
      var refreshCount = 0;

      await _pumpInvestigationResultWidget(
        tester,
        docState: _docStateWithPriorPendingInvestigation(),
        rpcClient: client,
        child: InvestigationResultCaptureList(
          pendingInvestigations: [_priorPendingInvestigation()],
          canEdit: true,
          onChanged: () => refreshCount++,
        ),
      );

      await _recordResultOnPendingInvestigation(tester, result: resultText);

      expect(client.paramsForFunction('record_investigation_result'), {
        'p_investigation_line_id': _priorInvestigationLineId,
        'p_result': resultText,
      });
      expect(refreshCount, 1);
      expect(find.byKey(Key('investigation_result_form_$_priorInvestigationLineId')), findsNothing);
    });

    testWidgets('hides record action when visit is read-only', (tester) async {
      await pumpEncounterWidget(
        tester,
        docState: _docStateWithPriorPendingInvestigation(),
        child: InvestigationResultCaptureList(
          pendingInvestigations: [_priorPendingInvestigation()],
          canEdit: false,
          onChanged: () {},
        ),
      );

      expect(find.byKey(Key('pending_investigation_$_priorInvestigationLineId')), findsOneWidget);
      expect(find.byKey(Key('investigation_result_record_$_priorInvestigationLineId')), findsNothing);
    });

    testWidgets('renders nothing when there are no pending investigations', (tester) async {
      await pumpEncounterWidget(
        tester,
        docState: sampleEncounterDocState(),
        child: InvestigationResultCaptureList(
          pendingInvestigations: const [],
          canEdit: true,
          onChanged: () {},
        ),
      );

      expect(find.text('Investigation results'), findsNothing);
    });
  });
}

class _DeferPersistenceHarness extends ConsumerStatefulWidget {
  const _DeferPersistenceHarness();

  @override
  ConsumerState<_DeferPersistenceHarness> createState() => _DeferPersistenceHarnessState();
}

class _DeferPersistenceHarnessState extends ConsumerState<_DeferPersistenceHarness> {
  late List<VisitInvestigation> pending;

  @override
  void initState() {
    super.initState();
    pending = [_priorPendingInvestigation()];
  }

  void _handleChanged() {
    final next = ref.read(visitDocumentationProvider(encounterTestVisitId).notifier).state.requireValue;

    setState(() {
      pending = next.visit.pendingInvestigations.where((investigation) => !investigation.hasResult).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(visitDocumentationProvider(encounterTestVisitId));
    if (pending.isEmpty) {
      return const SizedBox(key: Key('investigation_results_resolved'));
    }

    return InvestigationResultCaptureList(
      pendingInvestigations: pending,
      canEdit: true,
      visitId: encounterTestVisitId,
      deferPersistence: true,
      onChanged: _handleChanged,
    );
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
