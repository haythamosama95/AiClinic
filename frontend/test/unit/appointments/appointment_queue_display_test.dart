import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueDisplay', () {
    test('scheduleBadgeLabel uses canonical status labels', () {
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.scheduled), 'Scheduled');
      expect(AppointmentQueueDisplay.scheduleBadgeLabel(AppointmentStatus.checkedIn), 'Checked in');
    });

    test('estimateWaitDuration uses checkedInAt for checked-in patients', () {
      final checkedInAt = DateTime.utc(2026, 6, 4, 9, 30);
      final now = DateTime.utc(2026, 6, 4, 10);

      final wait = AppointmentQueueDisplay.estimateWaitDuration(
        item(status: AppointmentStatus.checkedIn, startTime: DateTime.utc(2026, 6, 4, 11), checkedInAt: checkedInAt),
        now: now,
      );

      expect(wait, const Duration(minutes: 30));
    });

    test('formatWaitedLabel renders minutes for short waits', () {
      expect(AppointmentQueueDisplay.formatWaitedLabel(const Duration(minutes: 15)), 'Waited: 15 mins');
    });

    test('formatWaitedLabel uses hour branch for waits at or above 60 minutes', () {
      expect(AppointmentQueueDisplay.formatWaitedLabel(const Duration(minutes: 75)), 'Waited: 1h 15m');
    });

    test('waitTierFor classifies wait urgency thresholds', () {
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 10)), AppointmentQueueWaitTier.normal);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 20)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 30)), AppointmentQueueWaitTier.critical);
    });

    test('waitPresentation combines wait label and tier', () {
      final now = DateTime.utc(2026, 6, 4, 10, 25);
      final checkedIn = item(
        status: AppointmentStatus.checkedIn,
        checkedInAt: DateTime.utc(2026, 6, 4, 10),
      );

      final (label, tier) = AppointmentQueueDisplay.waitPresentation(checkedIn, now: now);

      expect(label, 'Waiting: 25m');
      expect(tier, AppointmentQueueWaitTier.warning);
    });

    test('formatDurationLabel renders minutes, hours, and mixed durations', () {
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(minutes: 45)), '45m');
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(hours: 2)), '2h');
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(hours: 1, minutes: 15)), '1h 15m');
    });

    test('formatWaitLabel prefixes waiting duration', () {
      expect(AppointmentQueueDisplay.formatWaitLabel(const Duration(minutes: 12)), 'Waiting: 12m');
    });

    test('scheduleBadgeTone maps every queue status', () {
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.scheduled), AppBadgeTone.neutral);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.confirmed), AppBadgeTone.info);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.checkedIn), AppBadgeTone.success);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.inProgress), AppBadgeTone.warning);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.completed), AppBadgeTone.muted);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.cancelled), AppBadgeTone.destructive);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.noShow), AppBadgeTone.destructive);
      expect(AppointmentQueueDisplay.scheduleBadgeTone(AppointmentStatus.unknown), AppBadgeTone.neutral);
    });

    test('isScheduleRowDimmed dims completed and cancelled rows only', () {
      expect(AppointmentQueueDisplay.isScheduleRowDimmed(item(status: AppointmentStatus.completed)), isTrue);
      expect(AppointmentQueueDisplay.isScheduleRowDimmed(item(status: AppointmentStatus.cancelled)), isTrue);
      expect(AppointmentQueueDisplay.isScheduleRowDimmed(item(status: AppointmentStatus.scheduled)), isFalse);
    });

    test('indexClosestToNow returns 0 for an empty list', () {
      expect(AppointmentQueueDisplay.indexClosestToNow([], now: DateTime.utc(2026, 6, 4, 12)), 0);
    });

    test('computeStats omits trends when comparison items are absent', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.checkedIn, checkedInAt: now.subtract(const Duration(minutes: 10)))],
        now: now,
      );

      expect(stats.totalTrend, isNull);
      expect(stats.completedTrend, isNull);
      expect(stats.avgWaitTrend, isNull);
    });

    test('estimateWaitDuration uses slot anchor for non-checked-in patients', () {
      final now = DateTime.utc(2026, 6, 4, 10, 20);
      final scheduled = item(
        status: AppointmentStatus.scheduled,
        startTime: DateTime.utc(2026, 6, 4, 10),
      );

      expect(
        AppointmentQueueDisplay.estimateWaitDuration(scheduled, now: now),
        const Duration(minutes: 20),
      );
    });

    test('estimateSessionDuration returns zero for non-in-progress appointments', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final checkedIn = item(
        status: AppointmentStatus.checkedIn,
        inProgressAt: now.subtract(const Duration(minutes: 15)),
      );

      expect(AppointmentQueueDisplay.estimateSessionDuration(checkedIn, now: now), Duration.zero);
    });

    test('indexClosestToNow prefers the slot containing now', () {
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(id: 'early', startTime: start),
        item(id: 'current', startTime: start.add(const Duration(hours: 1))),
        item(id: 'later', startTime: start.add(const Duration(hours: 2))),
      ];
      final now = start.add(const Duration(hours: 1, minutes: 10));

      expect(AppointmentQueueDisplay.indexClosestToNow(items, now: now), 1);
    });

    test('indexClosestToNow picks nearest edge when now is outside all slots', () {
      final start = DateTime.utc(2026, 6, 4, 10);
      final items = [
        item(id: 'first', startTime: start),
        item(id: 'second', startTime: start.add(const Duration(hours: 2))),
      ];
      final between = start.add(const Duration(hours: 1));

      expect(AppointmentQueueDisplay.indexClosestToNow(items, now: between), 0);
      expect(AppointmentQueueDisplay.indexClosestToNow(items, now: start.add(const Duration(hours: 5))), 1);
    });

    test('queueDoctorLabel shows no preferred doctor when unassigned', () {
      final unassigned = item(doctorId: null, doctorName: null);
      expect(AppointmentQueueDisplay.queueDoctorLabel(unassigned), 'No preferred doctor');
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
            assigneeCount: 2,
          ),
        ],
        doctors: const [
          StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
          StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
        ],
      );
      final unassigned = item(doctorId: null, doctorName: null, startTime: DateTime.utc(2026, 6, 4, 10));

      expect(AppointmentQueueDisplay.queueDoctorLabel(unassigned, shiftLookup: lookup), 'No preferred doctor');
    });

    test('queueDoctorLabel shows assigned doctor name when present', () {
      final assigned = item(doctorId: 'doctor-a', doctorName: 'Dr Alpha');
      expect(AppointmentQueueDisplay.queueDoctorLabel(assigned), 'Dr Alpha');
    });

    test('status transition toasts describe the action taken', () {
      expect(
        AppointmentQueueDisplay.statusTransitionToastMessage(
          patientName: 'Jane Doe',
          newStatus: AppointmentStatus.confirmed,
        ),
        'Jane Doe confirmed.',
      );
      expect(
        AppointmentQueueDisplay.statusTransitionToastMessage(
          patientName: 'Jane Doe',
          newStatus: AppointmentStatus.checkedIn,
        ),
        'Jane Doe checked in.',
      );
      expect(
        AppointmentQueueDisplay.statusTransitionToastMessage(
          patientName: 'Jane Doe',
          newStatus: AppointmentStatus.inProgress,
        ),
        'Consultation started for Jane Doe.',
      );
      expect(
        AppointmentQueueDisplay.statusTransitionToastMessage(
          patientName: 'Jane Doe',
          newStatus: AppointmentStatus.cancelled,
        ),
        'Appointment cancelled for Jane Doe.',
      );
    });

    test('status revert toasts describe the undo action', () {
      expect(
        AppointmentQueueDisplay.statusRevertToastMessage(
          patientName: 'Jane Doe',
          revertedTo: AppointmentStatus.scheduled,
        ),
        'Confirmation undone for Jane Doe.',
      );
      expect(
        AppointmentQueueDisplay.statusRevertToastMessage(
          patientName: 'Jane Doe',
          revertedTo: AppointmentStatus.confirmed,
        ),
        'Check-in undone for Jane Doe.',
      );
      expect(
        AppointmentQueueDisplay.statusRevertToastMessage(
          patientName: 'Jane Doe',
          revertedTo: AppointmentStatus.checkedIn,
        ),
        'Consultation start undone for Jane Doe.',
      );
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
        AppointmentQueueDisplay.doctorInProgressBlockReason(waiting, [
          activeAlpha,
          activeBeta,
          waiting,
        ], shiftLookup: lookup),
        contains('All doctors on shift already have patients in progress'),
      );
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

      final stats = AppointmentQueueDisplay.computeStats(
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

      final stats = AppointmentQueueDisplay.computeStats(
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
      final partition = AppointmentQueueDisplay.partition([scheduled, noShow]);

      expect(partition.schedule.map((item) => item.id), ['ns1', 's1']);
      expect(AppointmentQueueDisplay.isScheduleRowDimmed(noShow), isFalse);
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
      final partition = AppointmentQueueDisplay.partition([late, early]);

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

      final stats = AppointmentQueueDisplay.computeStats(
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

      final stats = AppointmentQueueDisplay.computeStats(
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

      expect(AppointmentQueueDisplay.estimateSessionDuration(active, now: now), const Duration(minutes: 22));
      expect(
        AppointmentQueueDisplay.formatSessionLabel(AppointmentQueueDisplay.estimateSessionDuration(active, now: now)),
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

      expect(AppointmentQueueDisplay.indexClosestToNow(items, now: now), 1);
    });

    test('BUG-003: estimatedScheduleScrollOffset uses measured heights before fallback', () {
      final offset = AppointmentQueueDisplay.estimatedScheduleScrollOffset(
        targetIndex: 2,
        measuredRowHeights: const {0: 110, 1: 140},
        fallbackRowHeight: 92,
      );

      expect(offset, 250);
    });

    test('inProgressAppointmentForDoctor returns active visit for doctor', () {
      final active = item(id: 'active', status: AppointmentStatus.inProgress, doctorId: 'd1', doctorName: 'Dr Alpha');
      final waiting = item(id: 'waiting', status: AppointmentStatus.checkedIn, doctorId: 'd2');

      expect(AppointmentQueueDisplay.inProgressAppointmentForDoctor('d1', [active, waiting]), active);
      expect(AppointmentQueueDisplay.inProgressAppointmentForDoctor('d2', [active, waiting]), isNull);
    });

    test('BUG-009: inProgressAppointmentForDoctor matches unassigned in-progress slot', () {
      final unassignedActive = item(
        id: 'active',
        status: AppointmentStatus.inProgress,
        doctorId: null,
        doctorName: null,
      );

      expect(AppointmentQueueDisplay.inProgressAppointmentForDoctor(null, [unassignedActive]), unassignedActive);
      expect(AppointmentQueueDisplay.inProgressAppointmentForDoctor('', [unassignedActive]), unassignedActive);
      expect(AppointmentQueueDisplay.inProgressAppointmentForDoctor('d1', [unassignedActive]), isNull);
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

    test('trivial: computeStats without comparison omits trend fields', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.scheduled, id: 's1')],
        now: now,
      );

      expect(stats.total, 1);
      expect(stats.totalTrend, isNull);
      expect(stats.completedTrend, isNull);
      expect(stats.noShowTrend, isNull);
      expect(stats.avgWaitTrend, isNull);
      expect(stats.avgVisitTrend, isNull);
    });

    test('advanced: computeStats excludes cancelled and unknown from active total', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [
          item(status: AppointmentStatus.cancelled, id: 'c1'),
          item(status: AppointmentStatus.unknown, id: 'u1'),
          item(status: AppointmentStatus.scheduled, id: 's1'),
        ],
        now: now,
      );

      expect(stats.total, 1);
    });

    test('edge case: computeStats returns null averages when no wait or visit data', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.scheduled, id: 's1')],
        now: now,
      );

      expect(stats.avgWaitMinutes, isNull);
      expect(stats.avgVisitMinutes, isNull);
    });

    test('edge case: visit duration is null when inProgressAt is missing', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.inProgress, id: 'active', inProgressAt: null)],
        now: now,
      );

      expect(stats.avgVisitMinutes, isNull);
    });

    test('edge case: in-progress visit duration clamps negative elapsed to zero', () {
      final startedAt = DateTime.utc(2026, 6, 4, 12);
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.inProgress, id: 'active', inProgressAt: startedAt)],
        now: now,
      );

      expect(stats.avgVisitMinutes, 0);
    });

    test('invalid state: completed visit duration requires valid end after start', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [
          item(
            status: AppointmentStatus.completed,
            id: 'bad-end',
            inProgressAt: now,
            updatedAt: now.subtract(const Duration(minutes: 10)),
          ),
        ],
        now: now,
      );

      expect(stats.avgVisitMinutes, isNull);
    });

    test('edge case: wait duration is null without check-in timestamp', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.scheduled, id: 's1')],
        now: now,
      );

      expect(stats.avgWaitMinutes, isNull);
    });

    test('edge case: wait duration is null after patient moved to in-progress', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final stats = AppointmentQueueDisplay.computeStats(
        [
          item(
            status: AppointmentStatus.inProgress,
            id: 'active',
            checkedInAt: now.subtract(const Duration(minutes: 40)),
            inProgressAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
        now: now,
      );

      expect(stats.avgWaitMinutes, isNull);
    });

    test('advanced: percent change when previous count is zero', () {
      final now = DateTime.utc(2026, 6, 4, 12);

      final unchanged = AppointmentQueueDisplay.computeStats(
        const [],
        now: now,
        comparisonItems: const [],
        comparisonNow: now,
      );
      expect(unchanged.totalTrend?.percentChange, 0);

      final increased = AppointmentQueueDisplay.computeStats(
        [item(status: AppointmentStatus.scheduled, id: 's1')],
        now: now,
        comparisonItems: const [],
        comparisonNow: now,
      );
      expect(increased.totalTrend?.percentChange, 100);
    });

    test('advanced: partition waiting column equals checked-in patients sorted by slot', () {
      final early = item(
        status: AppointmentStatus.checkedIn,
        id: 'early',
        startTime: DateTime.utc(2026, 6, 4, 9),
      );
      final late = item(
        status: AppointmentStatus.checkedIn,
        id: 'late',
        startTime: DateTime.utc(2026, 6, 4, 11),
      );
      final scheduled = item(
        status: AppointmentStatus.scheduled,
        id: 'scheduled',
        startTime: DateTime.utc(2026, 6, 4, 10),
      );
      final partition = AppointmentQueueDisplay.partition([late, scheduled, early]);

      expect(partition.waiting.map((row) => row.id), ['early', 'late']);
      expect(partition.schedule.map((row) => row.id), ['early', 'scheduled', 'late']);
    });

    test('edge case: indexClosestToNow returns zero for empty schedule', () {
      expect(
        AppointmentQueueDisplay.indexClosestToNow(const [], now: DateTime.utc(2026, 6, 4, 12)),
        0,
      );
    });

    test('edge case: waitTierFor boundaries at warning and critical thresholds', () {
      expect(
        AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 19)),
        AppointmentQueueWaitTier.normal,
      );
      expect(
        AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 20)),
        AppointmentQueueWaitTier.warning,
      );
      expect(
        AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 29)),
        AppointmentQueueWaitTier.warning,
      );
      expect(
        AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 30)),
        AppointmentQueueWaitTier.critical,
      );
    });

    test('trivial: formatDurationLabel renders minutes and hours', () {
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(minutes: 45)), '45m');
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(minutes: 60)), '1h');
      expect(AppointmentQueueDisplay.formatDurationLabel(const Duration(minutes: 90)), '1h 30m');
    });

    test('advanced: scheduleBadgeTone maps every appointment status', () {
      const expected = {
        AppointmentStatus.scheduled: AppBadgeTone.neutral,
        AppointmentStatus.confirmed: AppBadgeTone.info,
        AppointmentStatus.checkedIn: AppBadgeTone.success,
        AppointmentStatus.inProgress: AppBadgeTone.warning,
        AppointmentStatus.completed: AppBadgeTone.muted,
        AppointmentStatus.cancelled: AppBadgeTone.destructive,
        AppointmentStatus.noShow: AppBadgeTone.destructive,
        AppointmentStatus.unknown: AppBadgeTone.neutral,
      };

      for (final entry in expected.entries) {
        expect(AppointmentQueueDisplay.scheduleBadgeTone(entry.key), entry.value);
      }
    });

    test('edge case: estimateSessionDuration is zero when visit is not in progress', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      expect(
        AppointmentQueueDisplay.estimateSessionDuration(
          item(status: AppointmentStatus.checkedIn),
          now: now,
        ),
        Duration.zero,
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
