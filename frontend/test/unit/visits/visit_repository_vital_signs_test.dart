import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  late VisitRpcTestClient client;
  late VisitRepository repository;

  setUp(() {
    client = VisitRpcTestClient();
    repository = VisitRepository(client);
  });

  group('VisitRepository.listPredefinedVitalSigns', () {
    test('trivial: invokes list_predefined_vital_signs with empty params', () async {
      final items = await repository.listPredefinedVitalSigns();

      expect(client.lastFunction, 'list_predefined_vital_signs');
<<<<<<< HEAD
      expect(client.lastParams, isEmpty);
=======
      expect(client.lastParams, isNull);
>>>>>>> master
      expect(items, hasLength(1));
      expect(items.first.name, 'Blood Pressure');
      expect(items.first.defaultUnit, 'mmHg');
    });

    test('advanced: parses default_unit on catalog items', () async {
      client.rpcResults['list_predefined_vital_signs'] = {
        'success': true,
        'data': {
          'items': [
            {'id': 'v1', 'name': 'Heart Rate', 'default_unit': 'bpm'},
            {'id': 'v2', 'name': 'Weight'},
          ],
        },
      };

      final items = await repository.listPredefinedVitalSigns();

      expect(items, hasLength(2));
      expect(items[0].defaultUnit, 'bpm');
      expect(items[1].defaultUnit, isNull);
    });

    test('edge case: null items returns empty list', () async {
      client.rpcResults['list_predefined_vital_signs'] = {'success': true, 'data': {'items': null}};

      final items = await repository.listPredefinedVitalSigns();

      expect(items, isEmpty);
    });

    test('edge case: empty items returns empty list', () async {
      client.rpcResults['list_predefined_vital_signs'] = {'success': true, 'data': {'items': []}};

      final items = await repository.listPredefinedVitalSigns();

      expect(items, isEmpty);
    });

    test('edge case: malformed rows are skipped', () async {
      client.rpcResults['list_predefined_vital_signs'] = {
        'success': true,
        'data': {
          'items': [
            {'id': '', 'name': 'Bad'},
            {'id': 'v1', 'name': 'Valid'},
          ],
        },
      };

      final items = await repository.listPredefinedVitalSigns();

      expect(items, hasLength(1));
      expect(items.first.name, 'Valid');
    });

    test('regression: FORBIDDEN propagates from RPC', () async {
      client.rpcResults['list_predefined_vital_signs'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.listPredefinedVitalSigns(),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.createVisitVitalSign', () {
    const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

    test('trivial: forwards required params to create_visit_vital_sign', () async {
      final id = await repository.createVisitVitalSign(visitId: visitId, name: 'Heart Rate', value: '72');

      expect(client.lastFunction, 'create_visit_vital_sign');
      expect(client.lastParams?['p_visit_id'], visitId);
      expect(client.lastParams?['p_name'], 'Heart Rate');
      expect(client.lastParams?['p_value'], '72');
      expect(client.lastParams?.containsKey('p_unit'), isFalse);
      expect(client.lastParams?.containsKey('p_predefined_vital_sign_id'), isFalse);
      expect(id, 'ssssssss-ssss-4sss-8sss-ssssssssssss');
    });

    test('advanced: forwards unit and predefined id when provided', () async {
      const predefinedId = 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv';

      await repository.createVisitVitalSign(
        visitId: visitId,
        name: '  Blood Pressure  ',
        value: ' 120/80 ',
        unit: 'mmHg',
        predefinedVitalSignId: predefinedId,
      );

      expect(client.lastParams?['p_name'], 'Blood Pressure');
      expect(client.lastParams?['p_value'], '120/80');
      expect(client.lastParams?['p_unit'], 'mmHg');
      expect(client.lastParams?['p_predefined_vital_sign_id'], predefinedId);
    });

    test('advanced: omits predefined id when blank', () async {
      await repository.createVisitVitalSign(
        visitId: visitId,
        name: 'Temp',
        value: '37',
        predefinedVitalSignId: '   ',
      );

      expect(client.lastParams?.containsKey('p_predefined_vital_sign_id'), isFalse);
    });

    test('stupid usage: blank visit id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.createVisitVitalSign(visitId: '  ', name: 'HR', value: '72'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: blank name or value throws INVALID_INPUT', () async {
      expect(
        () => repository.createVisitVitalSign(visitId: visitId, name: '', value: '72'),
        throwsA(isA<RpcFailure>()),
      );
      expect(
        () => repository.createVisitVitalSign(visitId: visitId, name: 'HR', value: '  '),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_visit_vital_sign'] = {'success': true, 'data': {'vital_sign_id': null}};

      expect(
        () => repository.createVisitVitalSign(visitId: visitId, name: 'HR', value: '72'),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: p_visit_id key name is stable', () async {
      await repository.createVisitVitalSign(visitId: visitId, name: 'HR', value: '72');

      expect(client.lastParams?.keys, containsAll(['p_visit_id', 'p_name', 'p_value']));
    });
  });

  group('VisitRepository.updateVisitVitalSign', () {
    const vitalSignId = 'ssssssss-ssss-4sss-8sss-ssssssssssss';

    test('trivial: forwards vital sign id to update_visit_vital_sign', () async {
      await repository.updateVisitVitalSign(vitalSignId: vitalSignId, name: 'Updated');

      expect(client.lastFunction, 'update_visit_vital_sign');
      expect(client.lastParams?['p_vital_sign_id'], vitalSignId);
      expect(client.lastParams?['p_name'], 'Updated');
    });

    test('advanced: forwards all optional fields when provided', () async {
      await repository.updateVisitVitalSign(
        vitalSignId: vitalSignId,
        name: 'BP',
        value: '130/85',
        unit: 'mmHg',
        predefinedVitalSignId: 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv',
      );

      expect(client.lastParams?['p_value'], '130/85');
      expect(client.lastParams?['p_unit'], 'mmHg');
      expect(client.lastParams?['p_predefined_vital_sign_id'], 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv');
    });

    test('advanced: omits unset optional params', () async {
      await repository.updateVisitVitalSign(vitalSignId: vitalSignId);

      expect(client.lastParams?.containsKey('p_name'), isFalse);
      expect(client.lastParams?.containsKey('p_value'), isFalse);
      expect(client.lastParams?.containsKey('p_unit'), isFalse);
      expect(client.lastParams?.containsKey('p_predefined_vital_sign_id'), isFalse);
    });

    test('stupid usage: blank vital sign id throws INVALID_INPUT', () async {
      expect(
        () => repository.updateVisitVitalSign(vitalSignId: ''),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: p_vital_sign_id key name is stable', () async {
      await repository.updateVisitVitalSign(vitalSignId: vitalSignId, value: '80');

      expect(client.lastParams?.keys, contains('p_vital_sign_id'));
    });
  });

  group('VisitRepository.archiveVisitVitalSign', () {
    test('trivial: forwards vital sign id to archive_visit_vital_sign', () async {
      const vitalSignId = 'ssssssss-ssss-4sss-8sss-ssssssssssss';

      await repository.archiveVisitVitalSign(vitalSignId: vitalSignId);

      expect(client.lastFunction, 'archive_visit_vital_sign');
      expect(client.lastParams?['p_vital_sign_id'], vitalSignId);
    });

    test('stupid usage: blank vital sign id throws INVALID_INPUT', () async {
      expect(
        () => repository.archiveVisitVitalSign(vitalSignId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });
  });

  group('VisitRepository.createPredefinedVitalSign', () {
    test('trivial: forwards name to create_predefined_vital_sign', () async {
      final result = await repository.createPredefinedVitalSign(name: 'Respiratory Rate');

      expect(client.lastFunction, 'create_predefined_vital_sign');
      expect(client.lastParams?['p_name'], 'Respiratory Rate');
      expect(client.lastParams?.containsKey('p_default_unit'), isFalse);
      expect(result.id, isNotEmpty);
      expect(result.created, isTrue);
    });

    test('advanced: forwards default unit when provided', () async {
      await repository.createPredefinedVitalSign(name: 'SpO2', defaultUnit: '%');

      expect(client.lastParams?['p_default_unit'], '%');
    });

    test('stupid usage: blank name throws INVALID_INPUT', () async {
      expect(
        () => repository.createPredefinedVitalSign(name: ''),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('edge case: trims name before RPC', () async {
      await repository.createPredefinedVitalSign(name: '  Weight  ');

      expect(client.lastParams?['p_name'], 'Weight');
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_predefined_vital_sign'] = {'success': true, 'data': {'id': null}};

      expect(
        () => repository.createPredefinedVitalSign(name: 'Weight'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
