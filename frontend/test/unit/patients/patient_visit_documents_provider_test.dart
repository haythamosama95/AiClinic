import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('B. Patient Detail — Functional (PD-F) documents provider', () {
    test('PD-F-009: loads documents via single list_patient_visit_attachments RPC', () async {
      final client = VisitRpcTestClient();
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

      final documents = await container.read(patientVisitDocumentsProvider(patientId).future);

      expect(documents, hasLength(1));
      expect(documents.first.attachment.label, 'Lab PDF');
      expect(client.paramsForFunction('get_visit'), isNull);
      expect(client.lastFunction, 'list_patient_visit_attachments');
      expect(client.lastParams?['p_patient_id'], patientId);
    });

    test('PD-F-010: preserves per-row can_download flags from RPC', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visit_attachments': {
            'success': true,
            'data': {
              'items': [
                {
                  'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
                  'visit_date': '2026-05-31',
                  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                  'file_type': 'pdf',
                  'label': 'Own upload',
                  'uploaded_by': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                  'uploaded_by_name': 'Uploader',
                  'size_bytes': 512,
                  'created_at': '2026-05-31T10:00:00.000Z',
                  'can_download': true,
                },
                {
                  'visit_id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
                  'visit_date': '2026-06-01',
                  'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  'file_type': 'pdf',
                  'label': 'Restricted',
                  'uploaded_by': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                  'uploaded_by_name': 'Other',
                  'size_bytes': 256,
                  'created_at': '2026-06-01T10:00:00.000Z',
                  'can_download': false,
                },
              ],
              'total_count': 2,
              'limit': 100,
              'offset': 0,
            },
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final documents = await container.read(patientVisitDocumentsProvider(patientId).future);

      expect(documents, hasLength(2));
      expect(documents[0].attachment.canDownload, isTrue);
      expect(documents[1].attachment.canDownload, isFalse);
    });
  });
}
