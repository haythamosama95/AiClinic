import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({
  required String code,
  String message = '',
  Map<String, dynamic>? data,
}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message, data: data));
}

void main() {
  group('PatientRpcFailure extension', () {
    group('isDuplicateWarning', () {
      test('true for DUPLICATE_WARNING code', () {
        expect(_failure(code: 'DUPLICATE_WARNING').isDuplicateWarning, isTrue);
      });

      test('false for other codes', () {
        expect(_failure(code: 'STALE_PATIENT').isDuplicateWarning, isFalse);
        expect(_failure(code: 'NOT_FOUND').isDuplicateWarning, isFalse);
        expect(_failure(code: 'FORBIDDEN').isDuplicateWarning, isFalse);
      });
    });

    group('isStalePatient', () {
      test('true for STALE_PATIENT code', () {
        expect(_failure(code: 'STALE_PATIENT').isStalePatient, isTrue);
      });

      test('false for other codes', () {
        expect(_failure(code: 'DUPLICATE_WARNING').isStalePatient, isFalse);
        expect(_failure(code: 'NOT_FOUND').isStalePatient, isFalse);
      });
    });

    group('duplicateCandidates', () {
      test('parses candidates from data payload', () {
        final failure = _failure(
          code: 'DUPLICATE_WARNING',
          data: {
            'candidates': [
              {'id': 'c1', 'full_name': 'Ahmed', 'branch_name': 'Main', 'phone': '201000000001'},
              {'id': 'c2', 'full_name': 'Mohamed', 'branch_name': 'South'},
            ],
          },
        );

        final candidates = failure.duplicateCandidates;
        expect(candidates, hasLength(2));
        expect(candidates[0].fullName, 'Ahmed');
        expect(candidates[0].phone, '201000000001');
        expect(candidates[1].fullName, 'Mohamed');
        expect(candidates[1].phone, isNull);
      });

      test('returns empty list when no candidates key', () {
        final failure = _failure(code: 'DUPLICATE_WARNING', data: {});
        expect(failure.duplicateCandidates, isEmpty);
      });

      test('returns empty list when data is null', () {
        final failure = _failure(code: 'DUPLICATE_WARNING');
        expect(failure.duplicateCandidates, isEmpty);
      });

      test('returns empty list when candidates is not a List', () {
        final failure = _failure(code: 'DUPLICATE_WARNING', data: {'candidates': 'not a list'});
        expect(failure.duplicateCandidates, isEmpty);
      });

      test('skips malformed candidate entries', () {
        final failure = _failure(
          code: 'DUPLICATE_WARNING',
          data: {
            'candidates': [
              {'id': '', 'full_name': 'Bad'},
              {'id': 'good', 'full_name': 'Good', 'branch_name': 'Main'},
            ],
          },
        );

        expect(failure.duplicateCandidates, hasLength(1));
        expect(failure.duplicateCandidates.first.id, 'good');
      });

      test('handles non-map entries in candidates list', () {
        final failure = _failure(
          code: 'DUPLICATE_WARNING',
          data: {
            'candidates': [42, null, 'string', {'id': 'ok', 'full_name': 'Valid', 'branch_name': 'B'}],
          },
        );

        expect(failure.duplicateCandidates, hasLength(1));
      });
    });
  });
}
