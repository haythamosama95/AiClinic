import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_metrics.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueMetrics', () {
    test('estimateWaitDuration uses checkedInAt for checked-in patients', () {
      final checkedInAt = DateTime.utc(2026, 6, 4, 9, 30);
      final now = DateTime.utc(2026, 6, 4, 10);

      final wait = AppointmentQueueMetrics.estimateWaitDuration(
        item(status: AppointmentStatus.checkedIn, startTime: DateTime.utc(2026, 6, 4, 11), checkedInAt: checkedInAt),
        now: now,
      );

      expect(wait, const Duration(minutes: 30));
    });

    test('computeStats compares against previous working day snapshot', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final todayItems = [
        item(status: AppointmentStatus.completed, id: 'c1'),
        item(status: AppointmentStatus.checkedIn, id: 'w1', checkedInAt: now.subtract(const Duration(minutes: 30))),
        item(status: AppointmentStatus.scheduled, id: 's1'),
      ];
      final previousItems = [
        item(status: AppointmentStatus.completed, id: 'pc1'),
        item(status: AppointmentStatus.scheduled, id: 'ps1'),
        item(status: AppointmentStatus.scheduled, id: 'ps2'),
      ];

      final stats = AppointmentQueueMetrics.computeStats(
        todayItems,
        now: now,
        comparisonItems: previousItems,
        comparisonNow: now,
      );

      expect(stats.total, 3);
      expect(stats.completed, 1);
      expect(stats.noShow, 0);
      expect(stats.avgVisitMinutes, isNull);
      expect(stats.totalTrend?.percentChange, closeTo(0, 0.01));
      expect(stats.completedTrend?.percentChange, closeTo(0, 0.01));
      expect(stats.noShowTrend?.percentChange, closeTo(0, 0.01));
      expect(stats.avgWaitTrend?.percentChange, closeTo(100, 0.01));
    });

    test('computeStats counts no-shows and compares against previous working day', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final todayItems = [
        item(status: AppointmentStatus.noShow, id: 'ns1'),
        item(status: AppointmentStatus.noShow, id: 'ns2'),
        item(status: AppointmentStatus.scheduled, id: 's1'),
      ];
      final previousItems = [
        item(status: AppointmentStatus.noShow, id: 'pns1'),
        item(status: AppointmentStatus.scheduled, id: 'ps1'),
      ];

      final stats = AppointmentQueueMetrics.computeStats(
        todayItems,
        now: now,
        comparisonItems: previousItems,
        comparisonNow: now,
      );

      expect(stats.total, 3);
      expect(stats.noShow, 2);
      expect(stats.noShowTrend?.percentChange, closeTo(100, 0.01));
    });

    test('partition keeps no-show appointments in the schedule column', () {
      final noShow = item(status: AppointmentStatus.noShow, id: 'ns1', startTime: DateTime.utc(2026, 6, 4, 9));
      final scheduled = item(status: AppointmentStatus.scheduled, id: 's1', startTime: DateTime.utc(2026, 6, 4, 11));
      final partition = AppointmentQueueMetrics.partition([scheduled, noShow]);

      expect(partition.schedule.map((item) => item.id), ['ns1', 's1']);
      expect(AppointmentQueueMetrics.isScheduleRowDimmed(noShow), isFalse);
    });

    test('partition orders checked-in patients by appointment start time', () {
      final early = item(
        status: AppointmentStatus.checkedIn,
        id: 'early',
        startTime: DateTime.utc(2026, 6, 4, 9),
        checkedInAt: DateTime.utc(2026, 6, 4, 8, 30),
      );
      final late = item(
        status: AppointmentStatus.checkedIn,
        id: 'late',
        startTime: DateTime.utc(2026, 6, 4, 11),
        checkedInAt: DateTime.utc(2026, 6, 4, 10, 45),
      );
      final partition = AppointmentQueueMetrics.partition([late, early]);

      expect(partition.waiting.map((item) => item.id), ['early', 'late']);
    });

    test('computeStats compares average visit duration using session timestamps', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final todayItems = [
        item(
          status: AppointmentStatus.completed,
          id: 'c1',
          inProgressAt: now.subtract(const Duration(minutes: 50)),
          updatedAt: now.subtract(const Duration(minutes: 10)),
        ),
        item(
          status: AppointmentStatus.inProgress,
          id: 'active',
          inProgressAt: now.subtract(const Duration(minutes: 20)),
        ),
      ];
      final comparisonNow = now.subtract(const Duration(days: 1));
      final previousItems = [
        item(
          status: AppointmentStatus.completed,
          id: 'pc1',
          inProgressAt: comparisonNow.subtract(const Duration(minutes: 30)),
          updatedAt: comparisonNow.subtract(const Duration(minutes: 10)),
        ),
      ];

      final stats = AppointmentQueueMetrics.computeStats(
        todayItems,
        now: now,
        comparisonItems: previousItems,
        comparisonNow: comparisonNow,
      );

      expect(stats.avgVisitMinutes, 30);
      expect(stats.avgVisitTrend?.percentChange, closeTo(50, 0.01));
    });

    test('computeStats compares average waited time using stored check-in timestamps', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final todayItems = [
        item(status: AppointmentStatus.checkedIn, id: 'w1', checkedInAt: now.subtract(const Duration(minutes: 20))),
        item(status: AppointmentStatus.checkedIn, id: 'w2', checkedInAt: now.subtract(const Duration(minutes: 40))),
      ];
      final comparisonNow = now.subtract(const Duration(days: 1));
      final previousItems = [
        item(
          status: AppointmentStatus.checkedIn,
          id: 'pw1',
          checkedInAt: comparisonNow.subtract(const Duration(minutes: 60)),
        ),
      ];

      final stats = AppointmentQueueMetrics.computeStats(
        todayItems,
        now: now,
        comparisonItems: previousItems,
        comparisonNow: comparisonNow,
      );

      expect(stats.avgWaitMinutes, 30);
      expect(stats.avgWaitTrend?.percentChange, closeTo(-50, 0.01));
    });

    test('estimateSessionDuration uses inProgressAt for active visits', () {
      final startedAt = DateTime.utc(2026, 6, 4, 10);
      final now = startedAt.add(const Duration(minutes: 22));
      final active = item(status: AppointmentStatus.inProgress, inProgressAt: startedAt);

      expect(AppointmentQueueMetrics.estimateSessionDuration(active, now: now), const Duration(minutes: 22));
    });

    test('inProgressAppointmentForDoctor returns active visit for doctor', () {
      final active = item(id: 'active', status: AppointmentStatus.inProgress, doctorId: 'd1', doctorName: 'Dr Alpha');
      final waiting = item(id: 'waiting', status: AppointmentStatus.checkedIn, doctorId: 'd2');

      expect(AppointmentQueueMetrics.inProgressAppointmentForDoctor('d1', [active, waiting]), active);
      expect(AppointmentQueueMetrics.inProgressAppointmentForDoctor('d2', [active, waiting]), isNull);
    });

    test('BUG-009: inProgressAppointmentForDoctor matches unassigned in-progress slot', () {
      final unassignedActive = item(
        id: 'active',
        status: AppointmentStatus.inProgress,
        doctorId: null,
        doctorName: null,
      );

      expect(AppointmentQueueMetrics.inProgressAppointmentForDoctor(null, [unassignedActive]), unassignedActive);
      expect(AppointmentQueueMetrics.inProgressAppointmentForDoctor('', [unassignedActive]), unassignedActive);
      expect(AppointmentQueueMetrics.inProgressAppointmentForDoctor('d1', [unassignedActive]), isNull);
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
        AppointmentQueueMetrics.doctorInProgressBlockReason(waiting, [active, waiting]),
        contains('already has a patient in progress'),
      );
      expect(AppointmentQueueMetrics.doctorInProgressBlockReason(active, [active, waiting]), isNull);
    });

    test('doctorInProgressBlockReason blocks start when all shift doctors are busy', () {
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
      final start = DateTime.utc(2026, 6, 4, 11);
      final activeAlpha = item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active-alpha',
      );
      final activeBeta = item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd2',
        doctorName: 'Dr Beta',
        id: 'active-beta',
      );
      final waiting = item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: null,
        doctorName: null,
        id: 'waiting',
      );

      expect(
        AppointmentQueueMetrics.doctorInProgressBlockReason(waiting, [
          activeAlpha,
          activeBeta,
          waiting,
        ], shiftLookup: lookup),
        contains('All doctors on shift already have patients in progress'),
      );
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
