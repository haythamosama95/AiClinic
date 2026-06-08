import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appointmentMessageForRpc', () {
    test('RPC_NOT_CONFIGURED explains incomplete database permissions', () {
      final message = appointmentMessageForRpc(
        RpcFailure(
          const RpcResult(
            success: false,
            errorCode: 'RPC_NOT_CONFIGURED',
            errorMessage: 'Appointment database permissions are incomplete.',
          ),
        ),
      );

      expect(message, contains('database permissions'));
      expect(message, contains('migrations'));
    });

    test('SCHEDULE_CONFLICT explains overlap', () {
      final message = appointmentMessageForRpc(
        RpcFailure(const RpcResult(success: false, errorCode: 'SCHEDULE_CONFLICT', errorMessage: 'Overlap')),
      );

      expect(message, contains('overlaps'));
    });

    test('PATIENT_ALREADY_BOOKED_SAME_DAY explains duplicate same-day booking', () {
      final message = appointmentMessageForRpc(
        RpcFailure(
          const RpcResult(success: false, errorCode: 'PATIENT_ALREADY_BOOKED_SAME_DAY', errorMessage: 'Already booked'),
        ),
      );

      expect(message.toLowerCase(), contains('same day'));
      expect(message.toLowerCase(), contains('existing appointment'));
    });

    test('INVALID_DOCTOR explains doctor assignment', () {
      final message = appointmentMessageForRpc(
        RpcFailure(const RpcResult(success: false, errorCode: 'INVALID_DOCTOR', errorMessage: 'Bad doctor')),
      );

      expect(message, contains('doctor'));
    });

    test('PATIENT_ARCHIVED explains archived patient', () {
      final message = appointmentMessageForRpc(
        RpcFailure(const RpcResult(success: false, errorCode: 'PATIENT_ARCHIVED', errorMessage: 'Archived')),
      );

      expect(message.toLowerCase(), contains('archived'));
    });

    test('NOT_FOUND explains missing appointment', () {
      final message = appointmentMessageForRpc(
        RpcFailure(
          const RpcResult(success: false, errorCode: 'NOT_FOUND', errorMessage: 'Appointment was not found.'),
        ),
      );

      expect(message.toLowerCase(), contains('appointment'));
      expect(message.toLowerCase(), contains('not found'));
    });

    test('NOT_FOUND explains missing patient', () {
      final message = appointmentMessageForRpc(
        RpcFailure(const RpcResult(success: false, errorCode: 'NOT_FOUND', errorMessage: 'Patient was not found.')),
      );

      expect(message.toLowerCase(), contains('patient'));
    });

    test('INVALID_BRANCH explains branch mismatch', () {
      final message = appointmentMessageForRpc(
        RpcFailure(
          const RpcResult(success: false, errorCode: 'INVALID_BRANCH', errorMessage: 'Branch is not valid for this session.'),
        ),
      );

      expect(message.toLowerCase(), contains('branch'));
    });
  });
}
