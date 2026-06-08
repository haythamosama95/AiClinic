import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({required String code, String message = 'backend message'}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
}

void main() {
  group('patientMessageForRpc', () {
    test('NOT_FOUND returns access-denied-style message', () {
      expect(
        patientMessageForRpc(_failure(code: 'NOT_FOUND')),
        'Patient was not found or you do not have access.',
      );
    });

    test('DUPLICATE_WARNING returns review message', () {
      expect(
        patientMessageForRpc(_failure(code: 'DUPLICATE_WARNING')),
        'Similar patients were found. Review the list before continuing.',
      );
    });

    test('STALE_PATIENT returns reload message', () {
      expect(
        patientMessageForRpc(_failure(code: 'STALE_PATIENT')),
        'This record was updated elsewhere. Reload and try again.',
      );
    });

    test('PATIENT_ARCHIVED returns archived message', () {
      expect(
        patientMessageForRpc(_failure(code: 'PATIENT_ARCHIVED')),
        'This patient is archived and is not available.',
      );
    });

    test('FORBIDDEN returns permission message', () {
      expect(
        patientMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to perform this action.',
      );
    });

    test('BRANCH_REQUIRED returns branch selection message', () {
      expect(
        patientMessageForRpc(_failure(code: 'BRANCH_REQUIRED')),
        'Select an active branch before registering a patient.',
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        patientMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Phone too short')),
        'Phone too short',
      );
    });

    test('unknown code falls through to backend message', () {
      expect(
        patientMessageForRpc(_failure(code: 'UNEXPECTED_ERROR', message: 'Something broke')),
        'Something broke',
      );
    });

    test('unknown code with default RpcFailure message', () {
      final failure = RpcFailure(const RpcResult(success: false));
      expect(patientMessageForRpc(failure), 'The clinic service rejected this request.');
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'NOT_FOUND',
        'DUPLICATE_WARNING',
        'STALE_PATIENT',
        'PATIENT_ARCHIVED',
        'FORBIDDEN',
        'BRANCH_REQUIRED',
        'INVALID_INPUT',
      ];

      for (final code in knownCodes) {
        final message = patientMessageForRpc(_failure(code: code));
        expect(message, isNotEmpty, reason: 'code=$code should produce non-empty message');
      }
    });
  });
}
