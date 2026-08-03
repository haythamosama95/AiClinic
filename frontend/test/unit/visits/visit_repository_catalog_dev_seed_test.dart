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

  group('VisitRepository.devSeedMedicationsCatalog', () {
    test('trivial: forwards names to dev_seed_medications_catalog', () async {
      final result = await repository.devSeedMedicationsCatalog(names: ['Aspirin', 'Ibuprofen']);

      expect(client.lastFunction, 'dev_seed_medications_catalog');
      expect(client.lastParams?['p_names'], ['Aspirin', 'Ibuprofen']);
      expect(result.inserted, 2);
      expect(result.requested, 2);
    });

    test('advanced: empty names skips RPC and returns zero counts', () async {
      final result = await repository.devSeedMedicationsCatalog(names: []);

      expect(client.lastFunction, isNull);
      expect(result.inserted, 0);
      expect(result.requested, 0);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['dev_seed_medications_catalog'] = {
        'success': true,
        'data': {'inserted': 'two'},
      };

      expect(
        () => repository.devSeedMedicationsCatalog(names: ['Aspirin']),
        throwsA(isA<StateError>()),
      );
    });

    test('invalid state: FORBIDDEN propagates from RPC', () async {
      client.rpcResults['dev_seed_medications_catalog'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Dev only',
      };

      expect(
        () => repository.devSeedMedicationsCatalog(names: ['Aspirin']),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.devSeedInvestigationsCatalog', () {
    test('trivial: forwards names to dev_seed_investigations_catalog', () async {
      final result = await repository.devSeedInvestigationsCatalog(names: ['CBC', 'Lipid Panel']);

      expect(client.lastFunction, 'dev_seed_investigations_catalog');
      expect(client.lastParams?['p_names'], ['CBC', 'Lipid Panel']);
      expect(result.inserted, 2);
      expect(result.requested, 2);
    });

    test('advanced: empty names skips RPC and returns zero counts', () async {
      final result = await repository.devSeedInvestigationsCatalog(names: []);

      expect(client.lastFunction, isNull);
      expect(result.inserted, 0);
      expect(result.requested, 0);
    });

    test('edge case: partial insert counts are parsed', () async {
      client.rpcResults['dev_seed_investigations_catalog'] = {
        'success': true,
        'data': {'inserted': 1, 'requested': 3},
      };

      final result = await repository.devSeedInvestigationsCatalog(names: ['A', 'B', 'C']);

      expect(result.inserted, 1);
      expect(result.requested, 3);
    });

    test('regression: p_names key name is stable', () async {
      await repository.devSeedInvestigationsCatalog(names: ['X-Ray']);

      expect(client.lastParams?.keys, contains('p_names'));
    });
  });

  group('VisitRepository.searchInvestigations (catalog)', () {
    test('trivial: default limit is 20', () async {
      await repository.searchInvestigations(query: 'cbc');

      expect(client.lastFunction, 'search_investigations');
      expect(client.lastParams?['p_query'], 'cbc');
      expect(client.lastParams?['p_limit'], 20);
    });

    test('edge case: very large limit is forwarded verbatim', () async {
      await repository.searchInvestigations(limit: 999999);

      expect(client.lastParams?['p_limit'], 999999);
    });
  });

  group('VisitRepository.createCatalogInvestigation (catalog)', () {
    test('regression: p_name key name is stable', () async {
      await repository.createCatalogInvestigation(name: 'MRI');

      expect(client.lastParams?.keys, contains('p_name'));
      expect(client.lastParams?['p_name'], 'MRI');
    });
  });
}
