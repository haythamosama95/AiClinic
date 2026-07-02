import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import 'visit_encounter_test_support.dart';

const _draftComplaint = 'Intermittent chest pain';

class _ModeToggleWorkspace extends ConsumerWidget {
  const _ModeToggleWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitDocumentationProvider(encounterTestVisitId)).value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerRight, child: EncounterWorkspaceModeToggle()),
        const SizedBox(height: 16),
        Expanded(
          child: EncounterWorkspaceShell(
            key: ValueKey(state.complaint),
            visitId: encounterTestVisitId,
            state: state,
            canEdit: true,
            canUploadAttachments: true,
            onRefresh: () {},
          ),
        ),
      ],
    );
  }
}

class _StaticVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _StaticVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

class _EmptyPatientSafetyNotifier extends PatientSafetyNotifier {
  _EmptyPatientSafetyNotifier() : super(encounterTestPatientId);

  @override
  Future<PatientSafetyContext> build() async => const PatientSafetyContext();
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

Future<void> _pumpModeToggleWorkspace(WidgetTester tester, VisitDocumentationState docState) async {
  const size = Size(1280, 900);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        visitDocumentationProvider(encounterTestVisitId).overrideWith(
          () => _StaticVisitDocumentationNotifier(docState),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
        home: Scaffold(
          body: SizedBox(width: size.width, height: size.height, child: const _ModeToggleWorkspace()),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pumpAndSettle();
}

ProviderContainer _workspaceContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
}

Future<void> _enterIntakeComplaint(WidgetTester tester, String text) async {
  final container = _workspaceContainer(tester);
  container.read(visitDocumentationProvider(encounterTestVisitId).notifier).updateComplaint(
        text,
        richDelta: [
          {'insert': '$text\n'},
        ],
      );
  await tester.pump();
  await tester.pumpAndSettle();
}

void _expectVisibleDraftComplaint(WidgetTester tester, {required String expected}) {
  final complaintField = find.byKey(const Key('clinical_note_complaint'));
  expect(complaintField, findsOneWidget);

  final editor = tester.state<QuillEditorState>(
    find.descendant(of: complaintField, matching: find.byType(QuillEditor), matchRoot: true),
  );
  final plain = editor.widget.controller.document.toPlainText().trim();
  expect(plain, expected);
}

void _expectDraftComplaint(WidgetTester tester, {required String expected}) {
  final container = _workspaceContainer(tester);
  final docState = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;

  expect(docState.complaint, expected);
  expect(docState.persistedVisit.documentation?.complaint ?? '', isEmpty);
}

void _expectGuidedMode(WidgetTester tester) {
  expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
  expect(find.byKey(const Key('expert_mode_accordion')), findsNothing);
  expect(_workspaceContainer(tester).read(workspaceModeProvider), WorkspaceMode.guided);
}

void _expectExpertMode(WidgetTester tester) {
  expect(find.byKey(const Key('expert_mode_accordion')), findsOneWidget);
  expect(find.byKey(const Key('expert_mode_phase_subjective')), findsOneWidget);
  expect(_workspaceContainer(tester).read(workspaceModeProvider), WorkspaceMode.expert);
}

Future<void> _tapMode(WidgetTester tester, Key modeKey) async {
  await tester.tap(find.byKey(modeKey));
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _rapidAlternateModeToggles(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await _tapMode(
      tester,
      i.isEven ? const Key('encounter_mode_expert') : const Key('encounter_mode_guided'),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  group('FE-003 — Mode toggle preserves draft content', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('expert → guided → expert keeps intake draft and provider state', (tester) async {
      final seedState = sampleEncounterDocState();
      await _pumpModeToggleWorkspace(tester, seedState);

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      await _enterIntakeComplaint(tester, _draftComplaint);
      _expectDraftComplaint(tester, expected: _draftComplaint);

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();
      _expectExpertMode(tester);
      _expectDraftComplaint(tester, expected: _draftComplaint);

      await tester.tap(find.byKey(const Key('encounter_mode_guided')));
      await tester.pumpAndSettle();
      _expectGuidedMode(tester);
      _expectVisibleDraftComplaint(tester, expected: _draftComplaint);

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();
      _expectExpertMode(tester);
      _expectDraftComplaint(tester, expected: _draftComplaint);
      _expectVisibleDraftComplaint(tester, expected: _draftComplaint);
      expect(tester.takeException(), isNull);
    });
  });

  group('ABUSE-003 — Rapid mode toggle spam', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('ten rapid guided/expert toggles stay crash-free with consistent draft', (tester) async {
      final errors = <Object>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = old);

      final seedState = sampleEncounterDocState();
      await _pumpModeToggleWorkspace(tester, seedState);
      await _enterIntakeComplaint(tester, _draftComplaint);
      _expectDraftComplaint(tester, expected: _draftComplaint);

      await _rapidAlternateModeToggles(tester, 10);

      expect(tester.takeException(), isNull);
      expect(errors, isEmpty);
      _expectGuidedMode(tester);
      _expectDraftComplaint(tester, expected: _draftComplaint);
    });

    testWidgets('rapid toggles ending in expert mode keep subjective draft visible', (tester) async {
      final seedState = sampleEncounterDocState();
      await _pumpModeToggleWorkspace(tester, seedState);
      await _enterIntakeComplaint(tester, _draftComplaint);

      for (var i = 0; i < 9; i++) {
        await _tapMode(
          tester,
          i.isEven ? const Key('encounter_mode_expert') : const Key('encounter_mode_guided'),
        );
      }
      await tester.pumpAndSettle();

      _expectExpertMode(tester);
      _expectDraftComplaint(tester, expected: _draftComplaint);
      _expectVisibleDraftComplaint(tester, expected: _draftComplaint);
      expect(tester.takeException(), isNull);
    });
  });
}
