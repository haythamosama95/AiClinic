import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appointmentMessageForRpc', () {
    String messageFor(String code, {String errorMessage = 'server detail'}) {
      return appointmentMessageForRpc(
        RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: errorMessage)),
      );
    }

    test('RPC_NOT_CONFIGURED explains incomplete database permissions', () {
      final message = messageFor('RPC_NOT_CONFIGURED', errorMessage: 'Appointment database permissions are incomplete.');

      expect(message, contains('database permissions'));
      expect(message, contains('migrations'));
    });

    test('RPC_NOT_APPLIED explains missing scheduling installation', () {
      final message = messageFor('RPC_NOT_APPLIED');

      expect(message, contains('not installed'));
      expect(message, contains('migrations'));
      expect(message, isNot(equals(messageFor('RPC_NOT_CONFIGURED'))));
    });

    test('SCHEDULE_CONFLICT explains overlap', () {
      final message = messageFor('SCHEDULE_CONFLICT', errorMessage: 'Overlap');

      expect(message, contains('overlaps'));
      expect(message, isNotEmpty);
    });

    test('PATIENT_ALREADY_BOOKED_SAME_DAY explains duplicate same-day booking', () {
      final message = messageFor('PATIENT_ALREADY_BOOKED_SAME_DAY', errorMessage: 'Already booked');

      expect(message.toLowerCase(), contains('same day'));
      expect(message.toLowerCase(), contains('existing appointment'));
    });

    test('DOCTOR_ALREADY_IN_PROGRESS explains active visit conflict', () {
      final message = messageFor('DOCTOR_ALREADY_IN_PROGRESS');

      expect(message.toLowerCase(), contains('in progress'));
      expect(message, isNot(equals(messageFor('VISIT_IN_PROGRESS'))));
    });

    test('VISIT_IN_PROGRESS explains undo blocked by active visit', () {
      final message = messageFor('VISIT_IN_PROGRESS');

      expect(message.toLowerCase(), contains('visit'));
      expect(message.toLowerCase(), contains('complete or cancel'));
    });

    test('INVALID_TRANSITION uses appointment-day message when server mentions appointment day', () {
      final message = messageFor('INVALID_TRANSITION', errorMessage: 'Only on Appointment Day');

      expect(message, contains('appointment day'));
      expect(message, isNot(equals(messageFor('INVALID_TRANSITION', errorMessage: 'generic failure'))));
    });

    test('INVALID_TRANSITION uses generic message for other server details', () {
      final message = messageFor('INVALID_TRANSITION', errorMessage: 'Status change denied');

      expect(message, 'That status change is not allowed for this appointment.');
    });

    test('PATIENT_ARCHIVED explains archived patient', () {
      final message = messageFor('PATIENT_ARCHIVED', errorMessage: 'Archived');

      expect(message.toLowerCase(), contains('archived'));
    });

    test('INVALID_DOCTOR explains doctor assignment', () {
      final message = messageFor('INVALID_DOCTOR', errorMessage: 'Bad doctor');

      expect(message, contains('doctor'));
    });

    test('FORBIDDEN explains missing permission', () {
      final message = messageFor('FORBIDDEN');

      expect(message.toLowerCase(), contains('permission'));
    });

    test('NOT_FOUND explains missing appointment', () {
      final message = messageFor('NOT_FOUND', errorMessage: 'Appointment was not found.');

      expect(message, 'Appointment was not found.');
    });

    test('NOT_FOUND explains missing patient', () {
      final message = messageFor('NOT_FOUND', errorMessage: 'Patient was not found.');

      expect(message, 'Patient was not found.');
    });

    test('NOT_FOUND uses generic record message when detail matches neither entity', () {
      final message = messageFor('NOT_FOUND', errorMessage: 'Branch record missing');

      expect(message, 'The requested record was not found.');
    });

    test('INVALID_BRANCH explains branch mismatch', () {
      final message = messageFor(
        'INVALID_BRANCH',
        errorMessage: 'Branch is not valid for this session.',
      );

      expect(message.toLowerCase(), contains('branch'));
    });

    test('INVALID_INPUT returns raw server message', () {
      const raw = 'Start time must be in the future.';
      final message = messageFor('INVALID_INPUT', errorMessage: raw);

      expect(message, raw);
      expect(message, isNot(equals(messageFor('FORBIDDEN'))));
    });

    test('edge case: unrecognised code returns raw server message', () {
      const raw = 'Unexpected database failure';
      final message = messageFor('SOME_NEW_CODE', errorMessage: raw);

      expect(message, raw);
    });

    test('advanced: every mapped code returns non-empty distinct copy', () {
      final messages = <String, String>{
        'SCHEDULE_CONFLICT': messageFor('SCHEDULE_CONFLICT'),
        'PATIENT_ALREADY_BOOKED_SAME_DAY': messageFor('PATIENT_ALREADY_BOOKED_SAME_DAY'),
        'DOCTOR_ALREADY_IN_PROGRESS': messageFor('DOCTOR_ALREADY_IN_PROGRESS'),
        'VISIT_IN_PROGRESS': messageFor('VISIT_IN_PROGRESS'),
        'INVALID_TRANSITION': messageFor('INVALID_TRANSITION', errorMessage: 'appointment day rule'),
        'PATIENT_ARCHIVED': messageFor('PATIENT_ARCHIVED'),
        'INVALID_DOCTOR': messageFor('INVALID_DOCTOR'),
        'RPC_NOT_CONFIGURED': messageFor('RPC_NOT_CONFIGURED'),
        'RPC_NOT_APPLIED': messageFor('RPC_NOT_APPLIED'),
        'FORBIDDEN': messageFor('FORBIDDEN'),
        'NOT_FOUND': messageFor('NOT_FOUND', errorMessage: 'patient missing'),
        'INVALID_BRANCH': messageFor('INVALID_BRANCH'),
        'INVALID_INPUT': messageFor('INVALID_INPUT', errorMessage: 'bad field'),
      };

      for (final entry in messages.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
      expect(messages.values.toSet().length, messages.length);
    });
  });
}
