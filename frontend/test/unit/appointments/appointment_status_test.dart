import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentStatus.tryParse', () {
    test('parses all lifecycle wire values', () {
      expect(AppointmentStatus.tryParse('scheduled'), AppointmentStatus.scheduled);
      expect(AppointmentStatus.tryParse('confirmed'), AppointmentStatus.confirmed);
      expect(AppointmentStatus.tryParse('checked_in'), AppointmentStatus.checkedIn);
      expect(AppointmentStatus.tryParse('in_progress'), AppointmentStatus.inProgress);
      expect(AppointmentStatus.tryParse('completed'), AppointmentStatus.completed);
      expect(AppointmentStatus.tryParse('cancelled'), AppointmentStatus.cancelled);
      expect(AppointmentStatus.tryParse('no_show'), AppointmentStatus.noShow);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AppointmentStatus.tryParse('  CHECKED_IN '), AppointmentStatus.checkedIn);
      expect(AppointmentStatus.tryParse('\tNO_SHOW\n'), AppointmentStatus.noShow);
    });

    test('returns null for empty or unrecognized values', () {
      expect(AppointmentStatus.tryParse(null), isNull);
      expect(AppointmentStatus.tryParse(''), isNull);
      expect(AppointmentStatus.tryParse('pending'), isNull);
      expect(AppointmentStatus.tryParse('checked-in'), isNull);
      expect(AppointmentStatus.tryParse('noshow'), isNull);
    });

    test('malformed user input does not throw', () {
      expect(() => AppointmentStatus.tryParse('null'), returnsNormally);
      expect(AppointmentStatus.tryParse('null'), isNull);
    });
  });

  group('AppointmentStatus.wireValue', () {
    test('round-trips with tryParse', () {
      for (final status in AppointmentStatus.values) {
        expect(AppointmentStatus.tryParse(status.wireValue), status);
      }
    });
  });

  group('AppointmentStatus.isTerminal', () {
    test('completed, cancelled, and no_show are terminal', () {
      expect(AppointmentStatus.completed.isTerminal, isTrue);
      expect(AppointmentStatus.cancelled.isTerminal, isTrue);
      expect(AppointmentStatus.noShow.isTerminal, isTrue);
    });

    test('active workflow statuses are not terminal', () {
      expect(AppointmentStatus.scheduled.isTerminal, isFalse);
      expect(AppointmentStatus.confirmed.isTerminal, isFalse);
      expect(AppointmentStatus.checkedIn.isTerminal, isFalse);
      expect(AppointmentStatus.inProgress.isTerminal, isFalse);
    });
  });

  group('AppointmentStatus.label', () {
    test('provides human-readable labels', () {
      expect(AppointmentStatus.inProgress.label, 'In progress');
      expect(AppointmentStatus.noShow.label, 'No-show');
    });
  });

  group('AppointmentStatus.canTransitionTo', () {
    test('confirmed may transition to checked_in, cancelled, or no_show', () {
      expect(AppointmentStatus.confirmed.canTransitionTo(AppointmentStatus.checkedIn), isTrue);
      expect(AppointmentStatus.confirmed.canTransitionTo(AppointmentStatus.cancelled), isTrue);
      expect(AppointmentStatus.confirmed.canTransitionTo(AppointmentStatus.noShow), isTrue);
      expect(AppointmentStatus.confirmed.canTransitionTo(AppointmentStatus.confirmed), isFalse);
      expect(AppointmentStatus.confirmed.canTransitionTo(AppointmentStatus.completed), isFalse);
    });

    test('scheduled may transition to confirmed or cancel paths', () {
      expect(AppointmentStatus.scheduled.canTransitionTo(AppointmentStatus.confirmed), isTrue);
      expect(AppointmentStatus.scheduled.canTransitionTo(AppointmentStatus.cancelled), isTrue);
      expect(AppointmentStatus.scheduled.canTransitionTo(AppointmentStatus.checkedIn), isFalse);
    });

    test('terminal statuses cannot transition', () {
      for (final status in AppointmentStatus.values) {
        expect(AppointmentStatus.completed.canTransitionTo(status), isFalse);
        expect(AppointmentStatus.cancelled.canTransitionTo(status), isFalse);
        expect(AppointmentStatus.noShow.canTransitionTo(status), isFalse);
      }
    });
  });
}
