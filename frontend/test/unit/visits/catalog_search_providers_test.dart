import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/catalog_search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  setUp(resetCatalogSearchGenerationsForTest);

  group('investigationSearchProvider', () {
    test('queries under 2 characters issue no RPC', () async {
      final client = VisitRpcTestClient();
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      final items = await container.read(investigationSearchProvider('a').future);

      expect(items, isEmpty);
      expect(client.rpcCalls.where((call) => call.fn == 'search_investigations'), isEmpty);
    });

    test('rapid successive queries within debounce window issue one RPC for final query', () async {
      final client = VisitRpcTestClient();
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      final first = container.read(investigationSearchProvider('am').future);
      final second = container.read(investigationSearchProvider('amo').future);
      final third = container.read(investigationSearchProvider('amox').future);

      final results = await Future.wait([first, second, third]);

      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      expect(results[2], hasLength(1));
      expect(results[2].first.name, 'Complete Blood Count');
      expect(client.rpcCalls.where((call) => call.fn == 'search_investigations'), hasLength(1));
      expect(client.lastParams?['p_query'], 'amox');
    });

    test('repository failure propagates as error state rather than empty list', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'search_investigations': {
            'success': false,
            'error_code': 'PERMISSION_DENIED',
            'error_message': 'No access',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(investigationSearchProvider('cbc').future),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'PERMISSION_DENIED')),
      );
    });
  });

  group('medicationSearchProvider', () {
    test('queries under 2 characters issue no RPC', () async {
      final client = VisitRpcTestClient();
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      final items = await container.read(medicationSearchProvider('a').future);

      expect(items, isEmpty);
      expect(client.rpcCalls.where((call) => call.fn == 'search_medications'), isEmpty);
    });
  });
}
