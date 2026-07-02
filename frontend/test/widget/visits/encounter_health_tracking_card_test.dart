import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_health_tracking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/patient_test_support.dart';
import 'visit_encounter_test_support.dart';

const _sampleAllergy = PatientAllergy(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  substance: 'Penicillin',
  reaction: 'Rash',
);

const _patientWithAllergy = PatientSafetyContext(
  allergies: [_sampleAllergy],
);

class _StaticPatientSafetyNotifier extends PatientSafetyNotifier {
  _StaticPatientSafetyNotifier(this._context) : super(encounterTestPatientId);

  final PatientSafetyContext _context;

  @override
  Future<PatientSafetyContext> build() async => _context;
}

class _StaticVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _StaticVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

Future<void> pumpEncounterWithSafety(
  WidgetTester tester, {
  required Widget child,
  required PatientSafetyContext safetyContext,
  VisitDocumentationState? docState,
  Size size = const Size(1280, 900),
  bool scrollable = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final overrides = <Override>[
    patientDetailProvider(
      encounterTestPatientId,
    ).overrideWith((ref) async => samplePatientDetail(id: encounterTestPatientId)),
    patientSafetyProvider(encounterTestPatientId).overrideWith(
      () => _StaticPatientSafetyNotifier(safetyContext),
    ),
  ];

  if (docState != null) {
    overrides.add(
      visitDocumentationProvider(encounterTestVisitId).overrideWith(
        () => _StaticVisitDocumentationNotifier(docState),
      ),
    );
  }

  final body = scrollable ? child : SizedBox(width: size.width, height: size.height, child: child);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        home: Scaffold(body: scrollable ? SingleChildScrollView(child: body) : body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void expectHealthTrackingCard(WidgetTester tester) {
  expect(find.byKey(const Key('patient_health_tracking_card')), findsOneWidget);
  expect(find.text('Health profile'), findsOneWidget);
  expect(find.text('Tracked across all visits'), findsOneWidget);
  expect(find.textContaining('Penicillin'), findsWidgets);
}

void expectHealthTrackingReadOnly(WidgetTester tester) {
  expect(find.byTooltip('Edit'), findsNothing);
  expect(find.byTooltip('Remove'), findsNothing);
  expect(find.text('Add allergy'), findsNothing);
  expect(find.text('Add condition'), findsNothing);
  expect(find.text('Add medication'), findsNothing);
}

void expectSummaryHealthAllergies(WidgetTester tester) {
  expect(find.text('ALLERGIES'), findsOneWidget);
  expect(find.textContaining('Penicillin · Rash'), findsOneWidget);
}

class _GuidedEncounterWorkspace extends StatelessWidget {
  const _GuidedEncounterWorkspace({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    this.trailing,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterJoinedHeader(visitId: visitId, visit: state.visit, onBack: () {}, trailing: trailing),
        const SizedBox(height: 16),
        Expanded(
          child: EncounterWorkspaceShell(
            visitId: visitId,
            state: state,
            canEdit: canEdit,
            canUploadAttachments: canUploadAttachments,
            onRefresh: onRefresh,
          ),
        ),
      ],
    );
  }
}

void main() {
  group('FE-006 — health tracking card visible on all phases', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders patient allergy data in the health profile shell', (tester) async {
      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        child: const PatientHealthTrackingCard(
          patientId: encounterTestPatientId,
          visitId: encounterTestVisitId,
          canEdit: true,
        ),
      );

      expectHealthTrackingCard(tester);
      expect(find.text('Allergies'), findsOneWidget);
      expect(find.textContaining('Penicillin - Rash'), findsOneWidget);
    });

    testWidgets('shows edit controls when canEdit is true', (tester) async {
      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        child: const PatientHealthTrackingCard(
          patientId: encounterTestPatientId,
          visitId: encounterTestVisitId,
          canEdit: true,
        ),
      );

      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsOneWidget);
      expect(find.byTooltip('Add allergy'), findsOneWidget);
      expect(find.text('Add condition'), findsOneWidget);
      expect(find.text('Add medication'), findsOneWidget);
    });

    testWidgets('is read-only when canEdit is false', (tester) async {
      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        child: const PatientHealthTrackingCard(
          patientId: encounterTestPatientId,
          canEdit: false,
        ),
      );

      expectHealthTrackingCard(tester);
      expectHealthTrackingReadOnly(tester);
    });

    testWidgets('shows health tracking card on Intake in guided workspace', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expectHealthTrackingCard(tester);
    });

    testWidgets('expert mode keeps health tracking card visible across documentation phases', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        scrollable: false,
        child: Column(
          children: [
            const Align(alignment: Alignment.centerRight, child: EncounterWorkspaceModeToggle()),
            Expanded(
              child: EncounterWorkspaceShell(
                visitId: encounterTestVisitId,
                state: state,
                canEdit: true,
                canUploadAttachments: true,
                onRefresh: () {},
              ),
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();

      for (final phase in EncounterPhase.documentationPhases) {
        expect(find.byKey(Key('expert_mode_phase_${phase.name}')), findsOneWidget);
      }
      expectHealthTrackingCard(tester);
    });

    testWidgets('guided navigation through Intake, Findings, and Treatment returns to health card on Intake', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expectHealthTrackingCard(tester);

      await tester.tap(find.byKey(const Key('encounter_step_objective')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_objective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);
      expect(find.byKey(const Key('patient_health_tracking_card')), findsNothing);

      await tester.tap(find.byKey(const Key('encounter_step_plan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_plan')), findsOneWidget);
      expect(find.byKey(const Key('patient_health_tracking_card')), findsNothing);

      await tester.tap(find.byKey(const Key('encounter_step_subjective')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expectHealthTrackingCard(tester);
    });

    testWidgets('shows health profile allergies on Summary after guided navigation', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
          trailing: Builder(
            builder: (context) {
              return TextButton(
                key: const Key('visit_finish_button'),
                onPressed: () {
                  ProviderScope.containerOf(context)
                      .read(encounterActivePhaseProvider(encounterTestVisitId).notifier)
                      .setPhase(EncounterPhase.review);
                },
                child: const Text('Finish Visit'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_step_objective')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('encounter_step_plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit_finish_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);
      expect(find.byKey(const Key('patient_health_tracking_card')), findsNothing);
      expectSummaryHealthAllergies(tester);
    });

    testWidgets('guided workspace is read-only when canEdit is false', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: false,
          canUploadAttachments: false,
          onRefresh: () {},
        ),
      );

      expectHealthTrackingCard(tester);
      expectHealthTrackingReadOnly(tester);
    });

    testWidgets('Summary review is read-only when canEdit is false', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWithSafety(
        tester,
        safetyContext: _patientWithAllergy,
        docState: state,
        child: EncounterReview(
          visitId: encounterTestVisitId,
          visit: state.visit,
          state: state,
          canEdit: false,
        ),
      );

      expectSummaryHealthAllergies(tester);
      expect(find.text('Edit'), findsNothing);
    });
  });
}
