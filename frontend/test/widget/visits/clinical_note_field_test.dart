import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_rich_text_editor.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_field.dart';

import '../../support/visit_encounter_test_support.dart';

List<dynamic> _richDeltaText(String text) => [
  {'insert': text},
  {'insert': '\n'},
];

class _RecordingVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _RecordingVisitDocumentationNotifier(this._seedState) : super(encounterTestVisitId);

  final VisitDocumentationState _seedState;
  VisitDocumentationState _currentState = sampleEncounterDocState();
  String? lastComplaint;
  List<dynamic>? lastComplaintDelta;
  int flushRegistrationCount = 0;

  @override
  Future<VisitDocumentationState> build() async {
    _currentState = _seedState;
    return _seedState;
  }

  void publishState(VisitDocumentationState next) {
    _currentState = next;
    // FamilyAsyncNotifier state setter; analyzer may not resolve while notifier is mid-refactor.
    // ignore: invalid_use_of_protected_member
    state = AsyncData(next);
  }

  @override
  void updateComplaint(String value, {List<dynamic>? richDelta}) {
    lastComplaint = value;
    lastComplaintDelta = richDelta;
    final nextDrafts = Map<ClinicalNoteSection, List<dynamic>>.from(_currentState.richTextDrafts);
    if (richDelta == null) {
      nextDrafts.remove(ClinicalNoteSection.complaint);
    } else {
      nextDrafts[ClinicalNoteSection.complaint] = richDelta;
    }
    publishState(_currentState.copyWith(complaint: value, richTextDrafts: nextDrafts));
  }

  @override
  void registerClinicalNoteFlush(VoidCallback callback) {
    flushRegistrationCount++;
    super.registerClinicalNoteFlush(callback);
  }
}


QuillController _quillController(WidgetTester tester) {
  return tester.state<QuillEditorState>(find.byType(QuillEditor)).widget.controller;
}

String _quillPlainText(WidgetTester tester) {
  return plainTextFromQuillDocument(_quillController(tester).document).trim();
}

Future<void> enterQuillText(WidgetTester tester, String text) async {
  final editorFinder = find.byType(QuillEditor);
  expect(editorFinder, findsOneWidget);
  await tester.tap(editorFinder);
  await tester.pump();
  final controller = _quillController(tester);
  final offset = controller.selection.baseOffset;
  controller.replaceText(offset, 0, text, null);
  await tester.pump();
}

Widget _wrap({
  required ProviderContainer container,
  required Widget child,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('ClinicalNoteField', () {
    testWidgets('typing updates the notifier draft', (tester) async {
      final notifier = _RecordingVisitDocumentationNotifier(sampleEncounterDocState());
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          container: container,
          child: const ClinicalNoteField(
            visitId: encounterTestVisitId,
            section: ClinicalNoteSection.complaint,
            fieldId: 'chief-complaint',
            editorId: 'chief-complaint-input',
            label: 'Chief complaint',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuillText(tester, 'Headache');

      expect(notifier.lastComplaint, 'Headache');
      expect(notifier.lastComplaintDelta, isNotNull);
    });

    testWidgets('external state change while unfocused updates the editor', (tester) async {
      final notifier = _RecordingVisitDocumentationNotifier(sampleEncounterDocState());
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          container: container,
          child: const ClinicalNoteField(
            visitId: encounterTestVisitId,
            section: ClinicalNoteSection.complaint,
            fieldId: 'chief-complaint',
            editorId: 'chief-complaint-input',
            label: 'Chief complaint',
          ),
        ),
      );
      await tester.pumpAndSettle();

      notifier.updateComplaint(
        'Synced complaint',
        richDelta: _richDeltaText('Synced complaint'),
      );
      await tester.pumpAndSettle();

      expect(_quillPlainText(tester), 'Synced complaint');
    });

    testWidgets('external state change while focused does not clobber the caret', (tester) async {
      final notifier = _RecordingVisitDocumentationNotifier(sampleEncounterDocState());
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          container: container,
          child: const ClinicalNoteField(
            visitId: encounterTestVisitId,
            section: ClinicalNoteSection.complaint,
            fieldId: 'chief-complaint',
            editorId: 'chief-complaint-input',
            label: 'Chief complaint',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuillText(tester, 'Local draft');

      notifier.updateComplaint(
        'Remote overwrite',
        richDelta: _richDeltaText('Remote overwrite'),
      );
      await tester.pumpAndSettle();

      expect(_quillPlainText(tester), 'Local draft');
    });

    testWidgets('disposes the controller without error when unmounted', (tester) async {
      final notifier = _RecordingVisitDocumentationNotifier(sampleEncounterDocState());
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrap(
          container: container,
          child: const ClinicalNoteField(
            visitId: encounterTestVisitId,
            section: ClinicalNoteSection.complaint,
            fieldId: 'chief-complaint',
            editorId: 'chief-complaint-input',
            label: 'Chief complaint',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(notifier.flushRegistrationCount, 1);

      await tester.pumpWidget(
        _wrap(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}
