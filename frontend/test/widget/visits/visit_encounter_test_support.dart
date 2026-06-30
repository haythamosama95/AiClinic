import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';

const encounterTestVisitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const encounterTestPatientId = '11111111-1111-4111-8111-111111111111';
const encounterTestBranchId = '44444444-4444-4444-8444-444444444444';

VisitDetail sampleEncounterVisit({String? visitType, List<VisitVitalSign> vitalSigns = const []}) {
  return VisitDetail(
    id: encounterTestVisitId,
    branchId: encounterTestBranchId,
    appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    patientId: encounterTestPatientId,
    doctorId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    doctorName: 'Dr Test',
    visitDate: DateTime.utc(2026, 5, 31),
    status: VisitStatus.inProgress,
    visitType: visitType,
    updatedAt: DateTime.utc(2026, 5, 31, 10),
    vitalSigns: vitalSigns,
  );
}

VisitDocumentationState sampleEncounterDocState({VisitDetail? visit}) {
  final resolved = visit ?? sampleEncounterVisit();
  return VisitDocumentationState(
    visit: resolved,
    complaint: '',
    history: '',
    examination: '',
    diagnosis: '',
    plan: '',
    expectedUpdatedAt: resolved.updatedAt ?? resolved.visitDate,
    predefinedVitalSigns: const [],
  );
}

Future<void> pumpEncounterWidget(
  WidgetTester tester, {
  required Widget child,
  VisitDocumentationState? docState,
  PatientDetail? patientDetail,
  Size size = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final overrides = <Override>[
    patientDetailProvider(
      encounterTestPatientId,
    ).overrideWith((ref) async => patientDetail ?? samplePatientDetail(id: encounterTestPatientId)),
  ];

  if (docState != null) {
    overrides.add(
      visitDocumentationProvider(encounterTestVisitId).overrideWith(() => _StaticVisitDocumentationNotifier(docState)),
    );
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
}

class _StaticVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _StaticVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

void expectUniquePhaseAncestor(WidgetTester tester, Key fieldKey, Key phaseKey, List<Key> otherPhaseKeys) {
  expect(find.byKey(fieldKey), findsOneWidget);
  expect(find.ancestor(of: find.byKey(fieldKey), matching: find.byKey(phaseKey)), findsOneWidget);
  for (final other in otherPhaseKeys) {
    expect(find.ancestor(of: find.byKey(fieldKey), matching: find.byKey(other)), findsNothing);
  }
}

const encounterPhaseKeys = <Key>[
  Key('encounter_phase_context'),
  Key('encounter_phase_subjective'),
  Key('encounter_phase_objective'),
  Key('encounter_phase_assessment'),
  Key('encounter_phase_plan'),
];

List<Key> otherPhaseKeysThan(Key phaseKey) => encounterPhaseKeys.where((key) => key != phaseKey).toList();
