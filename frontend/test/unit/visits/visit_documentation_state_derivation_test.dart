import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

void main() {
  test('effectiveVisit merges draft vitals; persistedVisit stays server-only', () {
    final persisted = sampleEncounterVisit();
    final draftSign = VisitVitalSign(id: 'draft:1', name: 'BP', value: '120/80');
    final state = VisitDocumentationState(
      persistedVisit: persisted,
      complaint: '',
      history: '',
      examination: '',
      diagnosis: '',
      plan: '',
      expectedUpdatedAt: persisted.updatedAt!,
      encounterDraft: VisitEncounterDraft(pendingVitalSigns: [draftSign]),
    );

    expect(state.persistedVisit.vitalSigns, isEmpty);
    expect(state.effectiveVisit.vitalSigns, hasLength(1));
    expect(state.effectiveVisit.vitalSigns.first.name, 'BP');
    expect(state.visit, equals(state.effectiveVisit));
  });
}
