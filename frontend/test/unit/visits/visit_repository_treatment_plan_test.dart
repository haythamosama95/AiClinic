import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  late VisitRpcTestClient testClient;
  late VisitRepository repo;

  setUp(() {
    testClient = VisitRpcTestClient();
    repo = VisitRepository(testClient);
  });

  group('searchMedications', () {
    test('invokes RPC with query and limit', () async {
      final items = await repo.searchMedications(query: 'amox', limit: 10);
      expect(items, hasLength(1));
      expect(items.first.name, 'Amoxicillin');
      expect(testClient.rpcLog.last, 'search_medications');
      final params = testClient.paramsForFunction('search_medications')!;
      expect(params['p_query'], 'amox');
      expect(params['p_limit'], 10);
    });
  });

  group('createCatalogMedication', () {
    test('throws on empty name', () {
      expect(() => repo.createCatalogMedication(name: '  '), throwsA(isA<RpcFailure>()));
    });

    test('returns create result on success', () async {
      final result = await repo.createCatalogMedication(name: 'Custom drug');
      expect(result.id, isNotEmpty);
      expect(result.name, 'Custom drug');
      expect(testClient.rpcLog.last, 'create_catalog_medication');
    });
  });

  group('createTreatmentPlan', () {
    test('throws on empty visitId', () {
      expect(
        () => repo.createTreatmentPlan(
          visitId: '',
          medicationName: 'Aspirin',
          dosage: '100mg',
          frequency: 'daily',
          duration: '7 days',
        ),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('throws on empty medicationName', () {
      expect(
        () => repo.createTreatmentPlan(
          visitId: 'abc',
          medicationName: '  ',
          dosage: '100mg',
          frequency: 'daily',
          duration: '7 days',
        ),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('throws when required dosage/frequency/duration missing', () {
      expect(
        () => repo.createTreatmentPlan(
          visitId: 'v1',
          medicationName: 'Drug',
          dosage: '',
          frequency: 'daily',
          duration: '7 days',
        ),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('returns treatment plan id on success', () async {
      final id = await repo.createTreatmentPlan(
        visitId: 'v1',
        medicationName: 'Amoxicillin',
        dosage: '500mg',
        frequency: 'TID',
        duration: '7 days',
      );
      expect(id, isNotEmpty);
      expect(testClient.rpcLog.last, 'create_treatment_plan');
      final params = testClient.paramsForFunction('create_treatment_plan')!;
      expect(params['p_visit_id'], 'v1');
      expect(params['p_medication_name'], 'Amoxicillin');
      expect(params['p_dosage'], '500mg');
      expect(params['p_frequency'], 'TID');
      expect(params['p_duration'], '7 days');
    });

    test('passes medication id and notes when provided', () async {
      await repo.createTreatmentPlan(
        visitId: 'v1',
        medicationName: 'Ibuprofen',
        medicationId: 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm',
        dosage: '200mg',
        frequency: 'twice daily',
        duration: '7 days',
        notes: 'Take with food',
      );
      final params = testClient.paramsForFunction('create_treatment_plan')!;
      expect(params['p_medication_id'], 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm');
      expect(params['p_notes'], 'Take with food');
      expect(params.containsKey('p_start_date'), isFalse);
      expect(params.containsKey('p_end_date'), isFalse);
    });
  });

  group('updateTreatmentPlan', () {
    test('throws on empty treatmentPlanId', () {
      expect(() => repo.updateTreatmentPlan(treatmentPlanId: ''), throwsA(isA<RpcFailure>()));
    });

    test('invokes RPC with correct params', () async {
      await repo.updateTreatmentPlan(treatmentPlanId: 'tp-1', medicationName: 'Updated Med', dosage: '100mg');
      expect(testClient.rpcLog.last, 'update_treatment_plan');
      final params = testClient.paramsForFunction('update_treatment_plan')!;
      expect(params['p_treatment_plan_id'], 'tp-1');
      expect(params['p_medication_name'], 'Updated Med');
      expect(params['p_dosage'], '100mg');
    });

    test('passes duration and medication id when provided', () async {
      await repo.updateTreatmentPlan(
        treatmentPlanId: 'tp-1',
        duration: '10 days',
        medicationId: 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm',
      );
      final params = testClient.paramsForFunction('update_treatment_plan')!;
      expect(params['p_duration'], '10 days');
      expect(params['p_medication_id'], 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm');
    });

    test('sends empty string for cleared optional field', () async {
      await repo.updateTreatmentPlan(treatmentPlanId: 'tp-1', medicationName: 'Updated Med', dosage: '');
      final params = testClient.paramsForFunction('update_treatment_plan')!;
      expect(params['p_dosage'], '');
      expect(params.containsKey('p_dosage'), isTrue);
    });
  });

  group('archiveTreatmentPlan', () {
    test('throws on empty treatmentPlanId', () {
      expect(() => repo.archiveTreatmentPlan(treatmentPlanId: ''), throwsA(isA<RpcFailure>()));
    });

    test('invokes archive RPC', () async {
      await repo.archiveTreatmentPlan(treatmentPlanId: 'tp-1');
      expect(testClient.rpcLog.last, 'archive_treatment_plan');
    });
  });
}
