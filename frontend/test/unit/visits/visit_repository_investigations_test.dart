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

  group('VisitRepository.searchInvestigations', () {
    test('trivial: invokes search_investigations with query and default limit', () async {
      final items = await repository.searchInvestigations(query: 'blood');

      expect(client.lastFunction, 'search_investigations');
      expect(client.lastParams?['p_query'], 'blood');
      expect(client.lastParams?['p_limit'], 20);
      expect(items, hasLength(1));
      expect(items.first.name, 'Complete Blood Count');
    });

    test('advanced: null query forwards empty string', () async {
      await repository.searchInvestigations();

      expect(client.lastParams?['p_query'], '');
      expect(client.lastParams?['p_limit'], 20);
    });

    test('advanced: trims query and forwards explicit limit', () async {
      await repository.searchInvestigations(query: '  cbc  ', limit: 5);

      expect(client.lastParams?['p_query'], 'cbc');
      expect(client.lastParams?['p_limit'], 5);
    });

    test('edge case: null items returns empty list', () async {
      client.rpcResults['search_investigations'] = {'success': true, 'data': {'items': null}};

      final items = await repository.searchInvestigations();

      expect(items, isEmpty);
    });

    test('edge case: zero limit is forwarded verbatim', () async {
      await repository.searchInvestigations(limit: 0);

      expect(client.lastParams?['p_limit'], 0);
    });
  });

  group('VisitRepository.createCatalogInvestigation', () {
    test('trivial: forwards name to create_catalog_investigation', () async {
      final result = await repository.createCatalogInvestigation(name: 'Lipid Panel');

      expect(client.lastFunction, 'create_catalog_investigation');
      expect(client.lastParams?['p_name'], 'Lipid Panel');
      expect(result.id, isNotEmpty);
      expect(result.name, 'Lipid Panel');
      expect(result.created, isTrue);
    });

    test('stupid usage: blank name throws INVALID_INPUT', () async {
      expect(
        () => repository.createCatalogInvestigation(name: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_catalog_investigation'] = {'success': true, 'data': {}};

      expect(
        () => repository.createCatalogInvestigation(name: 'X-Ray'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VisitRepository.createVisitInvestigation', () {
    const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

    test('trivial: forwards required params to create_visit_investigation', () async {
      final id = await repository.createVisitInvestigation(visitId: visitId, name: 'CBC');

      expect(client.lastFunction, 'create_visit_investigation');
      expect(client.lastParams?['p_visit_id'], visitId);
      expect(client.lastParams?['p_name'], 'CBC');
      expect(client.lastParams?.containsKey('p_note'), isFalse);
      expect(client.lastParams?.containsKey('p_investigation_id'), isFalse);
      expect(id, 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn');
    });

    test('advanced: forwards note and investigation id when provided', () async {
      const investigationId = 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii';

      await repository.createVisitInvestigation(
        visitId: visitId,
        name: '  CBC  ',
        note: 'Fasting',
        investigationId: investigationId,
      );

      expect(client.lastParams?['p_name'], 'CBC');
      expect(client.lastParams?['p_note'], 'Fasting');
      expect(client.lastParams?['p_investigation_id'], investigationId);
    });

    test('advanced: omits investigation id when blank', () async {
      await repository.createVisitInvestigation(visitId: visitId, name: 'CBC', investigationId: '  ');

      expect(client.lastParams?.containsKey('p_investigation_id'), isFalse);
    });

    test('stupid usage: blank visit id or name throws INVALID_INPUT', () async {
      expect(
        () => repository.createVisitInvestigation(visitId: '', name: 'CBC'),
        throwsA(isA<RpcFailure>()),
      );
      expect(
        () => repository.createVisitInvestigation(visitId: visitId, name: '  '),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_visit_investigation'] = {'success': true, 'data': {}};

      expect(
        () => repository.createVisitInvestigation(visitId: visitId, name: 'CBC'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VisitRepository.updateVisitInvestigation', () {
    const lineId = 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn';

    test('trivial: forwards line id and name to update_visit_investigation', () async {
      await repository.updateVisitInvestigation(investigationLineId: lineId, name: 'Updated CBC');

      expect(client.lastFunction, 'update_visit_investigation');
      expect(client.lastParams?['p_investigation_line_id'], lineId);
      expect(client.lastParams?['p_name'], 'Updated CBC');
      expect(client.lastParams?.containsKey('p_investigation_id'), isFalse);
      expect(client.lastParams?.containsKey('p_clear_investigation_id'), isFalse);
    });

    test('advanced: forwards note when provided', () async {
      await repository.updateVisitInvestigation(investigationLineId: lineId, note: 'Repeat in 2 weeks');

      expect(client.lastParams?['p_note'], 'Repeat in 2 weeks');
    });

    test('advanced: sets investigation id when updateInvestigationId is true', () async {
      const investigationId = 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii';

      await repository.updateVisitInvestigation(
        investigationLineId: lineId,
        investigationId: investigationId,
        updateInvestigationId: true,
      );

      expect(client.lastParams?['p_investigation_id'], investigationId);
      expect(client.lastParams?.containsKey('p_clear_investigation_id'), isFalse);
    });

    test('advanced: sends null investigation id when cleared with empty string', () async {
      await repository.updateVisitInvestigation(
        investigationLineId: lineId,
        investigationId: '',
        updateInvestigationId: true,
      );

      expect(client.lastParams?['p_investigation_id'], isNull);
      expect(client.lastParams?.containsKey('p_investigation_id'), isTrue);
    });

    test('advanced: sets p_clear_investigation_id when unlinking catalog entry', () async {
      await repository.updateVisitInvestigation(
        investigationLineId: lineId,
        updateInvestigationId: true,
      );

      expect(client.lastParams?['p_clear_investigation_id'], isTrue);
      expect(client.lastParams?.containsKey('p_investigation_id'), isFalse);
    });

    test('advanced: ignores investigation id when updateInvestigationId is false', () async {
      await repository.updateVisitInvestigation(
        investigationLineId: lineId,
        investigationId: 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii',
      );

      expect(client.lastParams?.containsKey('p_investigation_id'), isFalse);
      expect(client.lastParams?.containsKey('p_clear_investigation_id'), isFalse);
    });

    test('stupid usage: blank line id throws INVALID_INPUT', () async {
      expect(
        () => repository.updateVisitInvestigation(investigationLineId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });
  });

  group('VisitRepository.archiveVisitInvestigation', () {
    test('trivial: forwards line id to archive_visit_investigation', () async {
      const lineId = 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn';

      await repository.archiveVisitInvestigation(investigationLineId: lineId);

      expect(client.lastFunction, 'archive_visit_investigation');
      expect(client.lastParams?['p_investigation_line_id'], lineId);
    });

    test('stupid usage: blank line id throws INVALID_INPUT', () async {
      expect(
        () => repository.archiveVisitInvestigation(investigationLineId: ''),
        throwsA(isA<RpcFailure>()),
      );
    });
  });

  group('VisitRepository.recordInvestigationResult', () {
    const lineId = 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn';

    setUp(() {
      client.rpcResults['record_investigation_result'] = {
        'success': true,
        'data': {'result_recorded_at': '2026-05-31T14:30:00.000Z'},
      };
    });

    test('trivial: forwards line id and result to record_investigation_result', () async {
      final recordedAt = await repository.recordInvestigationResult(
        investigationLineId: lineId,
        result: 'Normal',
      );

      expect(client.lastFunction, 'record_investigation_result');
      expect(client.lastParams?['p_investigation_line_id'], lineId);
      expect(client.lastParams?['p_result'], 'Normal');
      expect(recordedAt, DateTime.parse('2026-05-31T14:30:00.000Z'));
    });

    test('advanced: omits result param when not provided', () async {
      await repository.recordInvestigationResult(investigationLineId: lineId);

      expect(client.lastParams?.containsKey('p_result'), isFalse);
    });

    test('edge case: null result_recorded_at returns null', () async {
      client.rpcResults['record_investigation_result'] = {'success': true, 'data': {}};

      final recordedAt = await repository.recordInvestigationResult(
        investigationLineId: lineId,
        result: 'Pending',
      );

      expect(recordedAt, isNull);
    });

    test('stupid usage: blank line id throws INVALID_INPUT', () async {
      expect(
        () => repository.recordInvestigationResult(investigationLineId: '  '),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('invalid state: NOT_FOUND propagates from RPC', () async {
      client.rpcResults['record_investigation_result'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Line missing',
      };

      expect(
        () => repository.recordInvestigationResult(investigationLineId: lineId, result: 'X'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });
  });
}
