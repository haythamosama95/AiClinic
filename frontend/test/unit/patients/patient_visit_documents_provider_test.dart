import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('patientVisitDocumentsProvider medium-severity regressions', () {
    test('M2: loads documents via single list_patient_visit_attachments RPC', () async {
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
  });
}
