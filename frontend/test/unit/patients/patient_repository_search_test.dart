import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository.searchPatients', () {
    late PatientRpcTestClient client;
    late PatientRepositoryImpl repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepositoryImpl(client);
    });

    test('trivial: trims query and sends branch scope', () async {
      await repository.searchPatients(
        query: '  ahmed  ',
        scope: PatientListScope.thisBranch,
        branchId: '44444444-4444-4444-8444-444444444444',
        limit: 10,
        offset: 5,
      );

      expect(client.lastFunction, 'search_patients');
      expect(client.lastParams?['p_query'], 'ahmed');
      expect(client.lastParams?['p_scope'], 'branch');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_limit'], 10);
      expect(client.lastParams?['p_offset'], 5);
    });

    test('browse mode omits p_query', () async {
      await repository.searchPatients(scope: PatientListScope.allBranches);

      expect(client.lastParams?.containsKey('p_query'), isFalse);
      expect(client.lastParams?['p_scope'], 'organization');
    });

    test('advanced: parses paginated items', () async {
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'full_name': 'Ahmed Hassan',
              'phone': '201234567890',
              'date_of_birth': '1990-05-15',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'branch_name': 'Main',
            },
          ],
          'total_count': 42,
          'limit': 25,
          'offset': 0,
        },
      };

      final page = await repository.searchPatients(scope: PatientListScope.allBranches);

      expect(page.items, hasLength(1));
      expect(page.items.first.fullName, 'Ahmed Hassan');
      expect(page.totalCount, 42);
    });

    test('invalid states: RPC failure propagates', () async {
      client.rpcResults['search_patients'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Query too short',
      };

      expect(
        () => repository.searchPatients(query: 'ab', scope: PatientListScope.allBranches),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: malformed item skipped without crashing', () async {
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {'id': 'bad-row'},
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'full_name': 'Valid',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'branch_name': 'Main',
            },
          ],
          'total_count': 1,
          'limit': 25,
          'offset': 0,
        },
      };

      final page = await repository.searchPatients(scope: PatientListScope.allBranches);

      expect(page.items, hasLength(1));
      expect(page.items.first.fullName, 'Valid');
    });
  });
}
