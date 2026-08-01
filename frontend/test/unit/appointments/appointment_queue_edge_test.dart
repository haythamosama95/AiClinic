import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 4, 12);

  group('queue edge cases', () {
    test('queueWaitMinutes never returns negative values for future slots', () {
      final upcoming = item(
        status: AppointmentStatus.scheduled,
        startTime: now.add(const Duration(hours: 2)),
      );

      expect(queueWaitMinutes(upcoming, now), 0);
    });

    test('queueDoctorIdleMinutes clamps future completion timestamps to zero', () {
      const doctor = QueueShiftDoctor(id: 'd1', name: 'Dr Alpha');
      final futureCompleted = item(
        status: AppointmentStatus.completed,
        doctorId: 'd1',
        updatedAt: now.add(const Duration(minutes: 10)),
      );

      expect(queueDoctorIdleMinutes(doctor, [futureCompleted], now: now), 0);
    });

    test('waitTierFor treats exactly 19 minutes as normal and 20 as warning', () {
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 19)), AppointmentQueueWaitTier.normal);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 20)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 29)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 30)), AppointmentQueueWaitTier.critical);
    });

    test('queueFilterByStatus preserves order for empty result sets', () {
      final items = [item(id: 'a', status: AppointmentStatus.scheduled)];

      expect(queueFilterByStatus(items, {AppointmentStatus.checkedIn}), isEmpty);
    });

    test('queueCheckedInPatients returns empty list when no checked-in patients exist', () {
      expect(
        queueCheckedInPatients([item(status: AppointmentStatus.scheduled)], now),
        isEmpty,
      );
    });

    test('computeStats handles all-cancelled day with zero active totals', () {
      final stats = AppointmentQueueDisplay.computeStats(
        [
          item(status: AppointmentStatus.cancelled, id: 'c1'),
          item(status: AppointmentStatus.cancelled, id: 'c2'),
        ],
        now: now,
      );

      expect(stats.total, 0);
      expect(stats.avgWaitMinutes, isNull);
    });

    test('queueDoctorLabel shows no preferred doctor when doctorId is null', () {
      final unassigned = item(doctorId: null);
      expect(AppointmentQueueDisplay.queueDoctorLabel(unassigned), 'No preferred doctor');
    });

    test('queueFilterByStatus does not duplicate matching rows', () {
      final scheduled = item(id: 'a', status: AppointmentStatus.scheduled);
      final confirmed = item(id: 'b', status: AppointmentStatus.confirmed);

      final filtered = queueFilterByStatus([scheduled, confirmed], {AppointmentStatus.scheduled});

      expect(filtered, hasLength(1));
      expect(filtered.single.id, 'a');
    });

    test('partition returns empty schedule and waiting for empty input', () {
      final partition = AppointmentQueueDisplay.partition(const []);

      expect(partition.schedule, isEmpty);
      expect(partition.waiting, isEmpty);
    });

    test('queueDoctorLagMinutes prefers in-progress lag over pending penalty', () {
      const doctor = QueueShiftDoctor(id: 'd1', name: 'Dr Alpha');
      final inProgress = item(
        id: 'active',
        status: AppointmentStatus.inProgress,
        doctorId: 'd1',
        inProgressAt: now.subtract(const Duration(minutes: 50)),
      );
      final pending = [
        item(id: 'p1', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
        item(id: 'p2', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
        item(id: 'p3', status: AppointmentStatus.checkedIn, doctorId: 'd1'),
      ];

      expect(queueDoctorLagMinutes(doctor, [inProgress, ...pending], now: now), 30);
    });
  });
}

AppointmentListItem item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  DateTime? updatedAt,
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
    inProgressAt: inProgressAt,
  );
}
