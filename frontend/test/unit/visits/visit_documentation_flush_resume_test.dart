import 'package:ai_clinic/features/visits/application/visit_encounter_flusher.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('C2 resumable encounter flush', () {
    test('removes each vital from draft after successful create and retries only remainder', () async {
      final client = _FlakyVitalSignRpcClient();
      final repo = VisitRepository(client);
      final flusher = VisitEncounterFlusher(
        repository: repo,
        attachmentService: VisitAttachmentService(client, repo),
      );
      final visit = sampleEncounterVisit();
      var liveDraft = VisitEncounterDraft(
        pendingVitalSigns: [
          const VisitVitalSign(id: 'draft:1', name: 'HR', value: '72'),
          const VisitVitalSign(id: 'draft:2', name: 'Temp', value: '37'),
          const VisitVitalSign(id: 'draft:3', name: 'SpO2', value: '98'),
        ],
      );

      final first = await flusher.flush(
        visit: visit,
        persistedVisit: visit,
        organizationId: 'org-1',
        initialDraft: liveDraft,
        onDraftUpdated: (draft) => liveDraft = draft,
      );

      expect(first.success, isFalse);
      expect(client.createVitalCalls, 3);
      expect(liveDraft.pendingVitalSigns, hasLength(1));
      expect(liveDraft.pendingVitalSigns.single.name, 'SpO2');

      client.failCreates = false;
      final second = await flusher.flush(
        visit: visit,
        persistedVisit: visit,
        organizationId: 'org-1',
        initialDraft: liveDraft,
        onDraftUpdated: (draft) => liveDraft = draft,
      );

      expect(second.success, isTrue);
      expect(client.createVitalCalls, 4);
      expect(liveDraft.pendingVitalSigns, isEmpty);
    });
  });
}

class _FlakyVitalSignRpcClient extends VisitRpcTestClient {
  int createVitalCalls = 0;
  bool failCreates = true;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_visit_vital_sign') {
      createVitalCalls++;
      if (failCreates && createVitalCalls == 3) {
        return FakePostgrestRpc({
          'success': false,
          'error_code': 'NETWORK',
          'error_message': 'transient',
        }) as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}
