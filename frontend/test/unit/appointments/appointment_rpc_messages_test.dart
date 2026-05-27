import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
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
  });
}
