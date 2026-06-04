import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  late VisitRpcTestClient client;
  late ProviderContainer container;

  setUp(() {
    client = VisitRpcTestClient();
    final authState = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        permissions: {PermissionKeys.visitsEditSoap},
        activeBranchId: branchId,
        branchIds: [branchId],
      ),
    );

    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(authState)),
        visitRepositoryProvider.overrideWithValue(VisitRepository(client)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('refreshTreatmentPlansPreservingDraft', () {
    test('merges treatment plans from get_visit without clearing SOAP draft', () async {
      final notifier = container.read(visitDocumentationProvider(visitId).notifier);
      await container.read(visitDocumentationProvider(visitId).future);

      notifier.updateSubjective('Unsaved chief complaint');
      notifier.updateObjective('Unsaved objective');

      client.rpcResults['get_visit'] = {
        'success': true,
        'data': {
          'id': visitId,
          'branch_id': branchId,
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'in_progress',
          'soap': {
            'subjective': null,
            'objective': null,
            'assessment': null,
            'plan': null,
            'specialty_form_json': {},
            'updated_at': '2026-05-31T10:00:00.000Z',
          },
          'treatment_plans': [
            {
              'id': 'tttttttt-tttt-4ttt-8ttt-tttttttttttt',
              'medication_name': 'Aspirin',
              'dosage': '81mg',
              'duration': '14 days',
            },
          ],
        },
      };

      await notifier.refreshTreatmentPlansPreservingDraft();

      final state = container.read(visitDocumentationProvider(visitId)).value!;
      expect(state.subjective, 'Unsaved chief complaint');
      expect(state.objective, 'Unsaved objective');
      expect(state.visit.treatmentPlans, hasLength(1));
      expect(state.visit.treatmentPlans.first.medicationName, 'Aspirin');
      expect(state.visit.treatmentPlans.first.duration, '14 days');
    });
  });
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
