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

  group('createTreatmentPlan', () {
    test('throws on empty visitId', () {
      expect(() => repo.createTreatmentPlan(visitId: '', medicationName: 'Aspirin'), throwsA(isA<RpcFailure>()));
    });

    test('throws on empty medicationName', () {
      expect(() => repo.createTreatmentPlan(visitId: 'abc', medicationName: '  '), throwsA(isA<RpcFailure>()));
    });

    test('returns treatment plan id on success', () async {
      final id = await repo.createTreatmentPlan(visitId: 'v1', medicationName: 'Amoxicillin');
      expect(id, isNotEmpty);
      expect(testClient.rpcLog.last, 'create_treatment_plan');
      final params = testClient.paramsForFunction('create_treatment_plan')!;
      expect(params['p_visit_id'], 'v1');
      expect(params['p_medication_name'], 'Amoxicillin');
    });

    test('passes optional fields', () async {
      await repo.createTreatmentPlan(
        visitId: 'v1',
        medicationName: 'Ibuprofen',
        dosage: '200mg',
        frequency: 'twice daily',
        duration: '7 days',
        notes: 'Take with food',
      );
      final params = testClient.paramsForFunction('create_treatment_plan')!;
      expect(params['p_dosage'], '200mg');
      expect(params['p_frequency'], 'twice daily');
      expect(params['p_duration'], '7 days');
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

    test('passes duration when provided', () async {
      await repo.updateTreatmentPlan(treatmentPlanId: 'tp-1', duration: '10 days');
      final params = testClient.paramsForFunction('update_treatment_plan')!;
      expect(params['p_duration'], '10 days');
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
