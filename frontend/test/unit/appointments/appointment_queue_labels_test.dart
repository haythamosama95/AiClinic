import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_metrics.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/formatting/appointment_queue_labels.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueLabels', () {
    test('scheduleBadgeLabel uses canonical status labels', () {
      expect(AppointmentQueueLabels.scheduleBadgeLabel(AppointmentStatus.scheduled), 'Scheduled');
      expect(AppointmentQueueLabels.scheduleBadgeLabel(AppointmentStatus.checkedIn), 'Checked in');
    });

    test('formatWaitedLabel renders minutes for short waits', () {
      expect(AppointmentQueueLabels.formatWaitedLabel(const Duration(minutes: 15)), 'Waited: 15 mins');
    });

    test('indexClosestToNow prefers the slot containing now', () {
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(id: 'early', startTime: start),
        item(id: 'current', startTime: start.add(const Duration(hours: 1))),
        item(id: 'later', startTime: start.add(const Duration(hours: 2))),
      ];
      final now = start.add(const Duration(hours: 1, minutes: 10));

      expect(AppointmentQueueLabels.indexClosestToNow(items, now: now), 1);
    });

    test('indexClosestToNow picks nearest edge when now is outside all slots', () {
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(id: 'first', startTime: start),
        item(id: 'second', startTime: start.add(const Duration(hours: 2))),
      ];
      final between = start.add(const Duration(hours: 1));

      expect(AppointmentQueueLabels.indexClosestToNow(items, now: between), 0);
      expect(AppointmentQueueLabels.indexClosestToNow(items, now: start.add(const Duration(hours: 5))), 1);
    });

    test('queueDoctorLabel shows no preferred doctor when unassigned', () {
      final unassigned = item(doctorId: null, doctorName: null);
      expect(AppointmentQueueLabels.queueDoctorLabel(unassigned), 'No preferred doctor');
    });

    test('queueDoctorLabel shows no preferred doctor even when shift doctors exist', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [
          ShiftListItem(
            id: 's1',
            branchId: 'b1',
            shiftDate: DateTime(2026, 6, 4),
            startTime: '09:00',
            endTime: '17:00',
            status: ShiftStatus.active,
            isUnassigned: false,
            assigneeNames: const ['Dr Alpha', 'Dr Beta'],
            assigneeIds: const ['d1', 'd2'],
            assigneeCount: 2,
          ),
        ],
        doctors: const [
          StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
          StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
        ],
      );
      final unassigned = item(doctorId: null, doctorName: null, startTime: DateTime.utc(2026, 6, 4, 10));

      expect(AppointmentQueueLabels.queueDoctorLabel(unassigned, shiftLookup: lookup), 'No preferred doctor');
    });

    test('queueDoctorLabel shows assigned doctor name when present', () {
      final assigned = item(doctorId: 'doctor-a', doctorName: 'Dr Alpha');
      expect(AppointmentQueueLabels.queueDoctorLabel(assigned), 'Dr Alpha');
    });

    test('formatSessionLabel formats active session duration', () {
      final startedAt = DateTime.utc(2026, 6, 4, 10);
      final now = startedAt.add(const Duration(minutes: 22));
      final active = item(status: AppointmentStatus.inProgress, inProgressAt: startedAt);

      expect(
        AppointmentQueueLabels.formatSessionLabel(AppointmentQueueMetrics.estimateSessionDuration(active, now: now)),
        'In session: 22m',
      );
    });

    test('BUG-008: indexClosestToNow prefers in-progress over slot proximity', () {
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(id: 'current-slot', startTime: start.add(const Duration(hours: 1)), status: AppointmentStatus.confirmed),
        item(id: 'in-progress', startTime: start, status: AppointmentStatus.inProgress),
      ];
      final now = start.add(const Duration(hours: 1, minutes: 10));

      expect(AppointmentQueueLabels.indexClosestToNow(items, now: now), 1);
    });

    test('BUG-003: estimatedScheduleScrollOffset uses measured heights before fallback', () {
      final offset = AppointmentQueueLabels.estimatedScheduleScrollOffset(
        targetIndex: 2,
        measuredRowHeights: const {0: 110, 1: 140},
        fallbackRowHeight: 92,
      );

      expect(offset, 250);
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
    checkedInAt: checkedInAt,
    inProgressAt: inProgressAt,
  );
}
