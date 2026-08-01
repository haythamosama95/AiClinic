import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 4, 12);

  group('queueIsOverdue', () {
    test('returns false for terminal and in-progress statuses', () {
      for (final status in [
        AppointmentStatus.completed,
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
        AppointmentStatus.inProgress,
      ]) {
        final past = item(status: status, startTime: now.subtract(const Duration(hours: 2)));
        expect(queueIsOverdue(past, now), isFalse, reason: status.name);
      }
    });

    test('returns true when scheduled slot is in the past', () {
      final overdue = item(
        status: AppointmentStatus.scheduled,
        startTime: now.subtract(const Duration(minutes: 15)),
      );
      expect(queueIsOverdue(overdue, now), isTrue);
    });

    test('returns false when scheduled slot is still in the future', () {
      final upcoming = item(
        status: AppointmentStatus.scheduled,
        startTime: now.add(const Duration(minutes: 30)),
      );
      expect(queueIsOverdue(upcoming, now), isFalse);
    });
  });

  group('queueSortForTriage', () {
    test('sorts overdue scheduled appointments first', () {
      final overdue = item(
        id: 'overdue',
        status: AppointmentStatus.scheduled,
        startTime: now.subtract(const Duration(minutes: 30)),
      );
      final checkedIn = item(
        id: 'checked-in',
        status: AppointmentStatus.checkedIn,
        startTime: now.subtract(const Duration(hours: 1)),
        checkedInAt: now.subtract(const Duration(minutes: 20)),
      );

      final sorted = queueSortForTriage([overdue, checkedIn], now);

      expect(sorted.first.id, 'overdue');
    });

    test('tie-breaks overdue scheduled by most minutes overdue first', () {
      final lessOverdue = item(
        id: 'less',
        status: AppointmentStatus.scheduled,
        startTime: now.subtract(const Duration(minutes: 10)),
      );
      final moreOverdue = item(
        id: 'more',
        status: AppointmentStatus.scheduled,
        startTime: now.subtract(const Duration(minutes: 40)),
      );

      final sorted = queueSortForTriage([lessOverdue, moreOverdue], now);

      expect(sorted.map((item) => item.id), ['more', 'less']);
    });

    test('orders by triage status priority when overdue tie is absent', () {
      final scheduled = item(
        id: 'scheduled',
        status: AppointmentStatus.scheduled,
        startTime: now.add(const Duration(hours: 1)),
      );
      final confirmed = item(
        id: 'confirmed',
        status: AppointmentStatus.confirmed,
        startTime: now.add(const Duration(hours: 1)),
      );
      final checkedIn = item(
        id: 'checked-in',
        status: AppointmentStatus.checkedIn,
        startTime: now,
        checkedInAt: now.subtract(const Duration(minutes: 5)),
      );

      final sorted = queueSortForTriage([scheduled, confirmed, checkedIn], now);

      expect(sorted.map((item) => item.id), ['checked-in', 'confirmed', 'scheduled']);
    });

    test('tie-breaks same status by slot start time', () {
      final later = item(
        id: 'later',
        status: AppointmentStatus.confirmed,
        startTime: now.add(const Duration(hours: 2)),
      );
      final earlier = item(
        id: 'earlier',
        status: AppointmentStatus.confirmed,
        startTime: now.add(const Duration(hours: 1)),
      );

      final sorted = queueSortForTriage([later, earlier], now);

      expect(sorted.map((item) => item.id), ['earlier', 'later']);
    });
  });

  group('queueFilterByStatus', () {
    test('returns items unchanged when filters are empty', () {
      final items = [
        item(id: 'a', status: AppointmentStatus.scheduled),
        item(id: 'b', status: AppointmentStatus.checkedIn),
      ];

      expect(queueFilterByStatus(items, {}), items);
    });

    test('filters to selected statuses', () {
      final items = [
        item(id: 'a', status: AppointmentStatus.scheduled),
        item(id: 'b', status: AppointmentStatus.checkedIn),
        item(id: 'c', status: AppointmentStatus.confirmed),
      ];

      final filtered = queueFilterByStatus(items, {
        AppointmentStatus.scheduled,
        AppointmentStatus.confirmed,
      });

      expect(filtered.map((item) => item.id), ['a', 'c']);
    });
  });

  group('queueCheckedInPatients', () {
    test('returns checked-in patients sorted by longest wait first', () {
      final shortWait = item(
        id: 'short',
        status: AppointmentStatus.checkedIn,
        startTime: now,
        checkedInAt: now.subtract(const Duration(minutes: 10)),
      );
      final longWait = item(
        id: 'long',
        status: AppointmentStatus.checkedIn,
        startTime: now,
        checkedInAt: now.subtract(const Duration(minutes: 45)),
      );

      final sorted = queueCheckedInPatients([shortWait, longWait], now);

      expect(sorted.map((item) => item.id), ['long', 'short']);
    });

    test('excludes non-checked-in appointments', () {
      final scheduled = item(id: 'scheduled', status: AppointmentStatus.scheduled);
      final checkedIn = item(
        id: 'checked-in',
        status: AppointmentStatus.checkedIn,
        checkedInAt: now.subtract(const Duration(minutes: 5)),
      );

      expect(queueCheckedInPatients([scheduled, checkedIn], now).map((item) => item.id), ['checked-in']);
    });
  });

  group('queueDoctorIdleMinutes', () {
    const doctor = QueueShiftDoctor(id: 'd1', name: 'Dr Alpha');

    test('returns minutes since latest completed visit for doctor', () {
      final completed = item(
        id: 'done',
        status: AppointmentStatus.completed,
        doctorId: 'd1',
        updatedAt: now.subtract(const Duration(minutes: 25)),
      );

      expect(queueDoctorIdleMinutes(doctor, [completed], now: now), 25);
    });

    test('returns zero when doctor has no completed visits today', () {
      expect(queueDoctorIdleMinutes(doctor, const [], now: now), 0);
    });
  });

  group('queueDoctorLagMinutes', () {
    const doctor = QueueShiftDoctor(id: 'd1', name: 'Dr Alpha');

    test('returns lag when in-progress session exceeds 20 minutes', () {
      final inProgress = item(
        id: 'active',
        status: AppointmentStatus.inProgress,
        doctorId: 'd1',
        inProgressAt: now.subtract(const Duration(minutes: 35)),
      );

      expect(queueDoctorLagMinutes(doctor, [inProgress], now: now), 15);
    });

    test('returns zero when in-progress session is within 20 minutes', () {
      final inProgress = item(
        id: 'active',
        status: AppointmentStatus.inProgress,
        doctorId: 'd1',
        inProgressAt: now.subtract(const Duration(minutes: 10)),
      );

      expect(queueDoctorLagMinutes(doctor, [inProgress], now: now), 0);
    });

    test('returns penalty when more than two checked-in patients are assigned', () {
      final pending = [
        item(id: 'p1', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
        item(id: 'p2', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
        item(id: 'p3', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
      ];

      expect(queueDoctorLagMinutes(doctor, pending, now: now), 30);
    });

    test('returns zero when pending load is within threshold', () {
      final pending = [
        item(id: 'p1', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
        item(id: 'p2', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
      ];

      expect(queueDoctorLagMinutes(doctor, pending, now: now), 0);
    });
  });
}

AppointmentListItem item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  DateTime? updatedAt,
  DateTime? checkedInAt,
  DateTime? inProgressAt,
  String? doctorId,
  String id = 'a1',
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: 'Pat',
    doctorId: doctorId,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    updatedAt: updatedAt,
    checkedInAt: checkedInAt,
    inProgressAt: inProgressAt,
  );
}
