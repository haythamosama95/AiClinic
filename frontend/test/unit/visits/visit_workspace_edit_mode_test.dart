import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

void main() {
  group('VisitDocumentationState.canEditWorkspace', () {
    test('completed visits are read-only until workspace edit mode is enabled', () {
      final visit = sampleEncounterVisit().copyWith(status: VisitStatus.completed);
      final viewing = VisitDocumentationState.fromVisit(visit);

      expect(viewing.canEditWorkspace(true), isFalse);

      final editing = viewing.copyWith(workspaceEditMode: WorkspaceEditMode.editing);
      expect(editing.canEditWorkspace(true), isTrue);
    });

    test('in-progress visits remain editable without workspace edit mode', () {
      final viewing = VisitDocumentationState.fromVisit(sampleEncounterVisit());

      expect(viewing.canEditWorkspace(true), isTrue);
    });
  });
}
