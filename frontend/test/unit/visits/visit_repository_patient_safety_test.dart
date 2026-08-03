import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

const _patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, dynamic> _patientSafetyPayload() => {
  'success': true,
  'data': {
    'allergies': [
      {'id': 'a1', 'substance': 'Penicillin', 'reaction': 'Severe'},
    ],
    'current_medications': [
      {'id': 'm1', 'name': 'Metformin', 'medication_id': 'med-1', 'note': '500mg'},
    ],
    'chronic_conditions': [
      {'id': 'c1', 'name': 'Type 2 Diabetes', 'note': 'Controlled'},
    ],
    'last_vitals': {
      'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'visit_date': '2026-05-30',
      'items': [
        {'name': 'BP', 'value': '120/80', 'unit': 'mmHg'},
      ],
    },
  },
};

void main() {
  late VisitRpcTestClient client;
  late VisitRepository repository;

  setUp(() {
    client = VisitRpcTestClient();
    repository = VisitRepository(client);
  });

  group('VisitRepository.getPatientSafetyContext', () {
    test('trivial: forwards patient id to get_patient_safety_context', () async {
      client.rpcResults['get_patient_safety_context'] = _patientSafetyPayload();

      final context = await repository.getPatientSafetyContext(patientId: _patientId);

      expect(client.lastFunction, 'get_patient_safety_context');
      expect(client.lastParams?['p_patient_id'], _patientId);
      expect(context.allergies, hasLength(1));
      expect(context.allergies.first.substance, 'Penicillin');
      expect(context.currentMedications.first.name, 'Metformin');
      expect(context.chronicConditions.first.name, 'Type 2 Diabetes');
      expect(context.lastVitals.visitId, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
      expect(context.lastVitals.items, hasLength(1));
      expect(context.hasStructuredData, isTrue);
    });

    test('advanced: null data returns empty context', () async {
      client.rpcResults['get_patient_safety_context'] = {'success': true, 'data': null};

      final context = await repository.getPatientSafetyContext(patientId: _patientId);

      expect(context.allergies, isEmpty);
      expect(context.currentMedications, isEmpty);
      expect(context.chronicConditions, isEmpty);
      expect(context.lastVitals.isEmpty, isTrue);
      expect(context.hasStructuredData, isFalse);
    });

    test('edge case: malformed list entries are skipped', () async {
      client.rpcResults['get_patient_safety_context'] = {
        'success': true,
        'data': {
          'allergies': [
            {'id': '', 'substance': 'Bad'},
            {'id': 'a2', 'substance': 'Latex'},
          ],
          'current_medications': null,
          'chronic_conditions': 'not-a-list',
          'last_vitals': null,
        },
      };

      final context = await repository.getPatientSafetyContext(patientId: _patientId);

      expect(context.allergies, hasLength(1));
      expect(context.allergies.first.substance, 'Latex');
      expect(context.currentMedications, isEmpty);
      expect(context.chronicConditions, isEmpty);
    });

    test('stupid usage: blank patient id throws INVALID_INPUT', () async {
      expect(
        () => repository.getPatientSafetyContext(patientId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('regression: FORBIDDEN propagates from RPC', () async {
      client.rpcResults['get_patient_safety_context'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.getPatientSafetyContext(patientId: _patientId),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.createPatientAllergy', () {
    setUp(() {
      client.rpcResults['create_patient_allergy'] = {
        'success': true,
        'data': {'id': 'allergy-1'},
      };
    });

    test('trivial: forwards substance to create_patient_allergy', () async {
      final id = await repository.createPatientAllergy(patientId: _patientId, substance: 'Penicillin');

      expect(client.lastFunction, 'create_patient_allergy');
      expect(client.lastParams?['p_patient_id'], _patientId);
      expect(client.lastParams?['p_substance'], 'Penicillin');
      expect(client.lastParams?.containsKey('p_reaction'), isFalse);
      expect(id, 'allergy-1');
    });

    test('advanced: forwards reaction when provided', () async {
      await repository.createPatientAllergy(
        patientId: _patientId,
        substance: '  Peanuts  ',
        reaction: 'Mild',
      );

      expect(client.lastParams?['p_substance'], 'Peanuts');
      expect(client.lastParams?['p_reaction'], 'Mild');
    });

    test('stupid usage: blank patient id or substance throws INVALID_INPUT', () async {
      expect(
        () => repository.createPatientAllergy(patientId: '', substance: 'X'),
        throwsA(isA<RpcFailure>()),
      );
      expect(
        () => repository.createPatientAllergy(patientId: _patientId, substance: '  '),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_patient_allergy'] = {'success': true, 'data': {}};

      expect(
        () => repository.createPatientAllergy(patientId: _patientId, substance: 'X'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VisitRepository.updatePatientAllergy', () {
    setUp(() {
      client.rpcResults['update_patient_allergy'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards allergy id to update_patient_allergy', () async {
      await repository.updatePatientAllergy(allergyId: 'allergy-1', substance: 'Latex');

      expect(client.lastFunction, 'update_patient_allergy');
      expect(client.lastParams?['p_allergy_id'], 'allergy-1');
      expect(client.lastParams?['p_substance'], 'Latex');
    });

    test('advanced: forwards reaction when provided', () async {
      await repository.updatePatientAllergy(allergyId: 'allergy-1', reaction: 'Severe');

      expect(client.lastParams?['p_reaction'], 'Severe');
    });

    test('stupid usage: blank allergy id throws INVALID_INPUT', () async {
      expect(
        () => repository.updatePatientAllergy(allergyId: '  '),
        throwsA(isA<RpcFailure>()),
      );
    });
  });

  group('VisitRepository.archivePatientAllergy', () {
    setUp(() {
      client.rpcResults['archive_patient_allergy'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards allergy id to archive_patient_allergy', () async {
      await repository.archivePatientAllergy(allergyId: 'allergy-1');

      expect(client.lastFunction, 'archive_patient_allergy');
      expect(client.lastParams?['p_allergy_id'], 'allergy-1');
    });
  });

  group('VisitRepository.createPatientMedication', () {
    setUp(() {
      client.rpcResults['create_patient_medication'] = {
        'success': true,
        'data': {'id': 'med-record-1'},
      };
    });

    test('trivial: forwards name to create_patient_medication', () async {
      final id = await repository.createPatientMedication(patientId: _patientId, name: 'Aspirin');

      expect(client.lastFunction, 'create_patient_medication');
      expect(client.lastParams?['p_patient_id'], _patientId);
      expect(client.lastParams?['p_name'], 'Aspirin');
      expect(client.lastParams?.containsKey('p_medication_id'), isFalse);
      expect(client.lastParams?.containsKey('p_note'), isFalse);
      expect(id, 'med-record-1');
    });

    test('advanced: forwards medication id and note when provided', () async {
      await repository.createPatientMedication(
        patientId: _patientId,
        name: '  Metformin  ',
        medicationId: 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm',
        note: 'Daily',
      );

      expect(client.lastParams?['p_name'], 'Metformin');
      expect(client.lastParams?['p_medication_id'], 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm');
      expect(client.lastParams?['p_note'], 'Daily');
    });

    test('advanced: omits medication id when blank', () async {
      await repository.createPatientMedication(patientId: _patientId, name: 'Aspirin', medicationId: '  ');

      expect(client.lastParams?.containsKey('p_medication_id'), isFalse);
    });
  });

  group('VisitRepository.updatePatientMedication', () {
    setUp(() {
      client.rpcResults['update_patient_medication'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards record id to update_patient_medication', () async {
      await repository.updatePatientMedication(medicationRecordId: 'med-record-1', name: 'Ibuprofen');

      expect(client.lastFunction, 'update_patient_medication');
      expect(client.lastParams?['p_medication_record_id'], 'med-record-1');
      expect(client.lastParams?['p_name'], 'Ibuprofen');
    });

    test('advanced: sends null medication id when cleared with empty string', () async {
      await repository.updatePatientMedication(
        medicationRecordId: 'med-record-1',
        medicationId: '',
      );

      expect(client.lastParams?['p_medication_id'], isNull);
      expect(client.lastParams?.containsKey('p_medication_id'), isTrue);
    });

    test('advanced: omits medication id param when not passed', () async {
      await repository.updatePatientMedication(medicationRecordId: 'med-record-1', note: 'Updated');

      expect(client.lastParams?.containsKey('p_medication_id'), isFalse);
      expect(client.lastParams?['p_note'], 'Updated');
    });
  });

  group('VisitRepository.archivePatientMedication', () {
    setUp(() {
      client.rpcResults['archive_patient_medication'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards record id to archive_patient_medication', () async {
      await repository.archivePatientMedication(medicationRecordId: 'med-record-1');

      expect(client.lastFunction, 'archive_patient_medication');
      expect(client.lastParams?['p_medication_record_id'], 'med-record-1');
    });
  });

  group('VisitRepository.createPatientChronicCondition', () {
    setUp(() {
      client.rpcResults['create_patient_chronic_condition'] = {
        'success': true,
        'data': {'id': 'condition-1'},
      };
    });

    test('trivial: forwards name to create_patient_chronic_condition', () async {
      final id = await repository.createPatientChronicCondition(patientId: _patientId, name: 'Hypertension');

      expect(client.lastFunction, 'create_patient_chronic_condition');
      expect(client.lastParams?['p_patient_id'], _patientId);
      expect(client.lastParams?['p_name'], 'Hypertension');
      expect(id, 'condition-1');
    });

    test('advanced: forwards note when provided', () async {
      await repository.createPatientChronicCondition(
        patientId: _patientId,
        name: '  Asthma  ',
        note: 'Mild',
      );

      expect(client.lastParams?['p_name'], 'Asthma');
      expect(client.lastParams?['p_note'], 'Mild');
    });
  });

  group('VisitRepository.updatePatientChronicCondition', () {
    setUp(() {
      client.rpcResults['update_patient_chronic_condition'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards condition id to update_patient_chronic_condition', () async {
      await repository.updatePatientChronicCondition(conditionId: 'condition-1', name: 'Updated');

      expect(client.lastFunction, 'update_patient_chronic_condition');
      expect(client.lastParams?['p_condition_id'], 'condition-1');
      expect(client.lastParams?['p_name'], 'Updated');
    });
  });

  group('VisitRepository.archivePatientChronicCondition', () {
    setUp(() {
      client.rpcResults['archive_patient_chronic_condition'] = {'success': true, 'data': {}};
    });

    test('trivial: forwards condition id to archive_patient_chronic_condition', () async {
      await repository.archivePatientChronicCondition(conditionId: 'condition-1');

      expect(client.lastFunction, 'archive_patient_chronic_condition');
      expect(client.lastParams?['p_condition_id'], 'condition-1');
    });

    test('stupid usage: blank condition id throws INVALID_INPUT', () async {
      expect(
        () => repository.archivePatientChronicCondition(conditionId: ''),
        throwsA(isA<RpcFailure>()),
      );
    });
  });
}
