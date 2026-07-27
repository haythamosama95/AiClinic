import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_attachments_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VisitAttachmentsState tracks pending attachment draft slice', () {
    const state = VisitAttachmentsState(deletedAttachmentIds: {'att-1'});
    expect(state.hasPendingDraft, isTrue);
    expect(state.toEncounterDraftSlice(), isA<VisitEncounterDraft>());
    expect(state.toEncounterDraftSlice().deletedAttachmentIds, {'att-1'});
  });
}
