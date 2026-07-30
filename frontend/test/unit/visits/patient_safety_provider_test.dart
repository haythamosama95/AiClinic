import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

const _patientIdA = encounterTestPatientId;
const _patientIdB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _safetyRpcPayload({
  bool includeStructuredData = true,
}) {
  if (!includeStructuredData) {
    return {
      'success': true,
      'data': {
        'allergies': <Map<String, dynamic>>[],
        'current_medications': <Map<String, dynamic>>[],
        'chronic_conditions': <Map<String, dynamic>>[],
        'last_vitals': {'items': <Map<String, dynamic>>[]},
      },
    };
  }
  return {
    'success': true,
    'data': {
      'allergies': [
        {'id': 'a-1', 'substance': 'Penicillin', 'reaction': 'Rash'},
      ],
      'current_medications': [
        {'id': 'm-1', 'name': 'Metformin'},
      ],
      'chronic_conditions': [
        {'id': 'c-1', 'name': 'Hypertension'},
      ],
      'last_vitals': {
        'visit_id': 'prior-visit',
        'visit_date': '2026-04-01',
        'items': [
          {'name': 'BP', 'value': '120/80', 'unit': 'mmHg'},
        ],
      },
    },
  };
}

ProviderContainer _createContainer(VisitRpcTestClient client) {
  final container = ProviderContainer(
    overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('PatientSafetyNotifier', () {
    late VisitRpcTestClient client;

    setUp(() {
      client = VisitRpcTestClient(
        rpcResults: {'get_patient_safety_context': _safetyRpcPayload()},
      );
    });

    test('trivial: build loads get_patient_safety_context with patient id param', () async {
      final container = _createContainer(client);
      final transitions = <AsyncValue<PatientSafetyContext>>[];
      container.listen(patientSafetyProvider(_patientIdA), (_, next) => transitions.add(next), fireImmediately: true);

      final context = await container.read(patientSafetyProvider(_patientIdA).future);

      expect(client.paramsForFunction('get_patient_safety_context')?['p_patient_id'], _patientIdA);
      expect(context.allergies, hasLength(1));
      expect(context.allergies.first.substance, 'Penicillin');
      expect(transitions.first, const AsyncLoading<PatientSafetyContext>());
      expect(transitions.last, isA<AsyncData<PatientSafetyContext>>());
    });

    test('trivial: success payload parses structured safety data', () async {
      final container = _createContainer(client);

      final context = await container.read(patientSafetyProvider(_patientIdA).future);

      expect(context.hasStructuredData, isTrue);
      expect(context.currentMedications, hasLength(1));
      expect(context.chronicConditions, hasLength(1));
      expect(context.lastVitals.isEmpty, isFalse);
      expect(context.lastVitals.items.first.name, 'BP');
    });

    test('edge case: empty payload has no structured data and empty last vitals', () async {
      client.rpcResults['get_patient_safety_context'] = _safetyRpcPayload(includeStructuredData: false);
      final container = _createContainer(client);

      final context = await container.read(patientSafetyProvider(_patientIdA).future);

      expect(context.hasStructuredData, isFalse);
      expect(context.allergies, isEmpty);
      expect(context.lastVitals.isEmpty, isTrue);
    });

    test('edge case: null RPC data yields empty context', () async {
      client.rpcResults['get_patient_safety_context'] = {'success': true, 'data': null};
      final container = _createContainer(client);

      final context = await container.read(patientSafetyProvider(_patientIdA).future);

      expect(context.hasStructuredData, isFalse);
      expect(context.lastVitals.isEmpty, isTrue);
    });

    test('invalid state: RPC failure surfaces AsyncError with code', () async {
      client.rpcResults['get_patient_safety_context'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Patient missing',
      };
      final container = _createContainer(client);
      final provider = patientSafetyProvider(_patientIdA);
      final transitions = <AsyncValue<PatientSafetyContext>>[];
      final subscription = container.listen(provider, (_, next) => transitions.add(next), fireImmediately: true);
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND'),
      );
      expect(transitions.any((value) => value is AsyncLoading), isTrue);
    });

    test('stupid usage: blank patient id throws StateError', () async {
      final container = _createContainer(client);

      await expectLater(
        container.read(patientSafetyProvider('  ').future),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Patient id is required.')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('advanced: refresh re-fetches and increments RPC call count', () async {
      final container = _createContainer(client);
      await container.read(patientSafetyProvider(_patientIdA).future);
      expect(client.rpcCalls.where((call) => call.fn == 'get_patient_safety_context').length, 1);

      client.rpcResults['get_patient_safety_context'] = _safetyRpcPayload(includeStructuredData: false);
      final transitions = <AsyncValue<PatientSafetyContext>>[];
      container.listen(patientSafetyProvider(_patientIdA), (_, next) => transitions.add(next), fireImmediately: true);

      await container.read(patientSafetyProvider(_patientIdA).notifier).refresh();

      expect(client.rpcCalls.where((call) => call.fn == 'get_patient_safety_context').length, 2);
      expect(container.read(patientSafetyProvider(_patientIdA)).requireValue.hasStructuredData, isFalse);
      expect(transitions.any((value) => value is AsyncLoading), isTrue);
      expect(transitions.last, isA<AsyncData<PatientSafetyContext>>());
    });

    test('edge case: family instances are independent per patient id', () async {
      final container = _createContainer(client);

      final contextA = await container.read(patientSafetyProvider(_patientIdA).future);

      client.rpcResults['get_patient_safety_context'] = {
        'success': true,
        'data': {
          'allergies': [
            {'id': 'a-2', 'substance': 'Latex'},
          ],
        },
      };
      final contextB = await container.read(patientSafetyProvider(_patientIdB).future);

      expect(contextA.allergies.first.substance, 'Penicillin');
      expect(contextB.allergies.first.substance, 'Latex');
      expect(
        client.rpcCalls.where((call) => call.fn == 'get_patient_safety_context').map((call) => call.params?['p_patient_id']),
        containsAll([_patientIdA, _patientIdB]),
      );
    });
  });
}
