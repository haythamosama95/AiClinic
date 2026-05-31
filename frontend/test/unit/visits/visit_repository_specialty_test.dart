import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitRepository specialty RPCs', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    group('getSpecialtyFormSchema', () {
      test('trivial: calls get_specialty_form_schema and returns schema_json map', () async {
        final schema = await repository.getSpecialtyFormSchema();

        expect(client.lastFunction, 'get_specialty_form_schema');
        expect(schema['type'], 'object');
        expect(schema['properties'], isA<Map>());
      });

      test('advanced: empty schema_json object when RPC returns non-map', () async {
        client.rpcResults['get_specialty_form_schema'] = {
          'success': true,
          'data': {'schema_json': 'not-a-map'},
        };

        final schema = await repository.getSpecialtyFormSchema();
        expect(schema, isEmpty);
      });

      test('edge case: coerces Map<dynamic, dynamic> schema_json', () async {
        client.rpcResults['get_specialty_form_schema'] = {
          'success': true,
          'data': {
            'schema_json': {
              'properties': {
                'pain_score': {'type': 'number'},
              },
            },
          },
        };

        final schema = await repository.getSpecialtyFormSchema();
        expect(schema['properties'], isA<Map>());
      });
    });

    group('saveSoapNote with specialty', () {
      test('trivial: forwards encoded specialty JSON on save', () async {
        const specialty = {'pain_score': 3, 'notes': 'mild'};

        await repository.saveSoapNote(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
          specialtyFormJson: specialty,
        );

        expect(client.lastParams?['p_specialty_form_json'], specialty);
      });

      test('invalid state: INVALID_INPUT from backend specialty validation', () async {
        client.rpcResults['save_soap_note'] = {
          'success': false,
          'error_code': 'INVALID_INPUT',
          'error_message': 'Specialty form data is not valid.',
        };

        expect(
          () => repository.saveSoapNote(
            visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
            specialtyFormJson: {'unknown_field': 1},
          ),
          throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
        );
      });

      test('edge case: omits p_specialty_form_json when specialtyFormJson is null', () async {
        await repository.saveSoapNote(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
          subjective: 'SOAP only',
        );

        expect(client.lastParams?['p_specialty_form_json'], isNull);
      });
    });
  });
}
