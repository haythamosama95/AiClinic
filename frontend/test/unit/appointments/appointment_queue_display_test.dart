import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueDisplay', () {
    test('scheduleBadgeLabel uses canonical status labels', () {
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.scheduled), 'Scheduled');
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.checkedIn), 'Checked in');
    });

    test('estimateWaitDuration uses updatedAt for checked-in patients', () {
      final checkedInAt = DateTime.utc(2026, 6, 4, 9, 30);
      final now = DateTime.utc(2026, 6, 4, 10);

      final wait = AppointmentQueueDisplay.estimateWaitDuration(
        item(status: AppointmentStatus.checkedIn, startTime: DateTime.utc(2026, 6, 4, 11), updatedAt: checkedInAt),
        now: now,
      );

      expect(wait, const Duration(minutes: 30));
    });

    test('formatWaitedLabel renders minutes for short waits', () {
      expect(AppointmentQueueDisplay.formatWaitedLabel(const Duration(minutes: 15)), 'Waited: 15 mins');
    });

    test('activeSessionsFor returns one session per doctor', () {
      final doctorA = 'doc-a';
      final doctorB = 'doc-b';
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(
          status: AppointmentStatus.inProgress,
          startTime: start,
          doctorId: doctorA,
          doctorName: 'Dr Alpha',
          id: 'a1',
        ),
        item(
          status: AppointmentStatus.inProgress,
          startTime: start.add(const Duration(hours: 1)),
          doctorId: doctorB,
          doctorName: 'Dr Beta',
          id: 'a2',
        ),
        item(
          status: AppointmentStatus.inProgress,
          startTime: start.add(const Duration(minutes: 30)),
          doctorId: doctorA,
          doctorName: 'Dr Alpha',
          id: 'a3',
        ),
      ];

      final sessions = AppointmentQueueDisplay.activeSessionsFor(items);
      expect(sessions, hasLength(2));
      expect(sessions.map((session) => session.id), containsAll(['a1', 'a2']));
    });

    test('doctorInProgressBlockReason blocks start when doctor already in session', () {
      final doctorId = 'doc-a';
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: doctorId,
        doctorName: 'Dr Alpha',
        id: 'active',
      );
      final waiting = item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: doctorId,
        doctorName: 'Dr Alpha',
        id: 'waiting',
      );

      expect(
        AppointmentQueueDisplay.doctorInProgressBlockReason(waiting, [active, waiting]),
        contains('already has a patient in progress'),
      );
      expect(AppointmentQueueDisplay.doctorInProgressBlockReason(active, [active, waiting]), isNull);
    });
  });
}

AppointmentListItem item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  DateTime? updatedAt,
  String? doctorId,
  String? doctorName,
  String id = 'a1',
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: 'Pat',
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    updatedAt: updatedAt,
  );
}
