import 'dart:async';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/widgets/data/app_metric_stat_card.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_journey_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_widget.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appointment_queue_fe_test_support.dart';
import '../../helpers/appointment_queue_test_support.dart' show queueTodayLocal;

void main() {
  final dayStart = queueTodayLocal(hour: 8);
  final queueNow = queueFeFixedNow;

  group('FE-001 — Wide layout three-column grid', () {
    testWidgets('schedule left with doctors and checked-in stacked on the right', (tester) async {
      final items = hourlyScheduleItems(dayStart: dayStart, count: 6);
      await pumpQueuePage(
        tester,
        viewport: queueWideViewport,
        queueState: AppointmentQueueState(items: items),
      );

      final schedule = columnTitleCenter(tester, 'Appointments');
      final doctors = columnTitleCenter(tester, 'Doctors');
      final checkedIn = columnTitleCenter(tester, 'Checked in');

      expect(schedule.dx, lessThan(doctors.dx));
      expect(schedule.dx, lessThan(checkedIn.dx));
      expect((doctors.dx - checkedIn.dx).abs(), lessThan(16));
      expect(doctors.dy, lessThan(checkedIn.dy));

      expect(pageScrollView(), findsNothing);

      final listView = scheduleListView(tester);
      expect(listView.shrinkWrap, isFalse);
      expect(listView.physics, isNull);
    });
  });

  group('FE-002 — Narrow layout stacked columns', () {
    testWidgets('schedule, doctors, and checked in stack vertically below 1100px', (tester) async {
      final items = hourlyScheduleItems(dayStart: dayStart, count: 4);
      await pumpQueuePage(
        tester,
        viewport: queueNarrowViewport,
        queueState: AppointmentQueueState(items: items),
      );

      final schedule = columnTitleCenter(tester, 'Appointments');
      final doctors = columnTitleCenter(tester, 'Doctors');
      final checkedIn = columnTitleCenter(tester, 'Checked in');

      expect(schedule.dy, lessThan(doctors.dy));
      expect(doctors.dy, lessThan(checkedIn.dy));
    });
  });

  group('FE-003 — Short viewport page scroll', () {
    testWidgets('outer page scrolls and column lists defer scrolling', (tester) async {
      final items = [
        ...hourlyScheduleItems(dayStart: dayStart, count: 12),
        queueItem(
          id: 'waiting-1',
          patientName: 'Waiting Patient',
          startTime: dayStart.add(const Duration(hours: 12)),
          status: AppointmentStatus.checkedIn,
          checkedInAt: queueNow,
        ),
      ];
      await pumpQueuePage(
        tester,
        viewport: queueShortViewport,
        queueState: AppointmentQueueState(items: items),
        shiftLookup: sampleShiftLookup(),
      );

      expect(pageScrollView(), findsOneWidget);

      for (final listView in [scheduleListView(tester), sessionListView(tester), waitingListView(tester)]) {
        expect(listView.shrinkWrap, isTrue);
        expect(listView.physics, isA<NeverScrollableScrollPhysics>());
      }
    });
  });

  group('FE-004 — Stats banner compact vs wide', () {
    AppointmentQueueStats statsWithTrends() {
      final now = queueFeFixedNow;
      final today = [
        queueItem(id: 'c1', patientName: 'A', startTime: dayStart, status: AppointmentStatus.completed),
        queueItem(
          id: 'w1',
          patientName: 'B',
          startTime: dayStart.add(const Duration(hours: 1)),
          status: AppointmentStatus.checkedIn,
          checkedInAt: now.subtract(const Duration(minutes: 20)),
        ),
        queueItem(id: 's1', patientName: 'C', startTime: dayStart.add(const Duration(hours: 2))),
      ];
      final previous = [
        queueItem(id: 'pc1', patientName: 'P', startTime: dayStart, status: AppointmentStatus.completed),
        queueItem(id: 'ps1', patientName: 'Q', startTime: dayStart.add(const Duration(hours: 1))),
        queueItem(id: 'ps2', patientName: 'R', startTime: dayStart.add(const Duration(hours: 2))),
      ];
      return AppointmentQueueDisplay.computeStats(today, now: now, comparisonItems: previous, comparisonNow: now);
    }

    testWidgets('wide layout shows a single row of five metric cards with trend arrows', (tester) async {
      await pumpQueueWidget(
        tester,
        viewport: queueStatsWideViewport,
        child: AppointmentQueueStatsBanner(stats: statsWithTrends()),
      );

      expect(find.byType(Wrap), findsNothing);
      expect(find.byType(AppMetricStatCard), findsNWidgets(5));
      expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);
    });

    testWidgets('compact layout wraps metric cards in two columns', (tester) async {
      await pumpQueueWidget(
        tester,
        viewport: queueStatsCompactViewport,
        child: AppointmentQueueStatsBanner(stats: statsWithTrends()),
      );

      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(AppMetricStatCard), findsNWidgets(5));
      expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);
    });
  });

  group('FE-005 — Schedule timeline focus bubble', () {
    testWidgets('closest slot uses teal focus bubble and past segments use active line color', (tester) async {
      final items = [
        queueItem(id: 'early', patientName: 'Early', startTime: dayStart),
        queueItem(id: 'current', patientName: 'Current', startTime: dayStart.add(const Duration(hours: 4))),
        queueItem(id: 'later', patientName: 'Later', startTime: dayStart.add(const Duration(hours: 5))),
      ];

      await pumpQueueWidget(
        tester,
        child: AppointmentQueueScheduleColumn(items: items, now: queueNow),
      );
      await tester.pumpAndSettle();

      final painters = scheduleTimelinePainters(tester);
      expect(painters, isNotEmpty);

      final hasFocusBubble = painters.any((painter) {
        final ring = (painter as dynamic).bubbleRingColor as Color;
        return ring == focusBubbleColor;
      });
      expect(hasFocusBubble, isTrue);

      final colors = AppTheme.light().extension<SemanticColors>()!;
      final pastUsesActiveLine = painters.any((painter) {
        final above = (painter as dynamic).lineAboveColor as Color;
        final below = (painter as dynamic).lineBelowColor as Color;
        return above == colors.primary || below == colors.primary;
      });
      expect(pastUsesActiveLine, isTrue);
    });
  });

  group('FE-006 — Checked-in patient tap scrolls schedule', () {
    testWidgets('tapping waiting patient scrolls schedule to the appointment row', (tester) async {
      final farStart = dayStart.add(const Duration(hours: 11));
      final items = [
        ...hourlyScheduleItems(dayStart: dayStart, count: 11),
        queueItem(
          id: 'far-checked-in',
          patientName: 'Far Patient',
          startTime: farStart,
          status: AppointmentStatus.checkedIn,
          checkedInAt: queueNow.subtract(const Duration(minutes: 10)),
        ),
      ];

      await pumpQueuePage(
        tester,
        viewport: queueWideViewport,
        queueState: AppointmentQueueState(items: items),
        settle: false,
      );
      await tester.pumpAndSettle();

      final farFinder = find.text('Far Patient');
      expect(farFinder, findsWidgets);

      await tester.tap(find.descendant(of: find.byType(AppointmentQueueWaitingColumn), matching: farFinder).last);
      await tester.pumpAndSettle();

      final farRect = tester.getRect(farFinder.last);
      expect(isRectInViewport(tester, farRect), isTrue);

      await tester.pump(AppointmentQueueScheduleColumn.flashDuration);
      expect(tester.takeException(), isNull);
    });
  });

  group('FE-007 — Doctor row tap when in progress', () {
    testWidgets('in-progress doctor scrolls to patient and idle doctor is not tappable', (tester) async {
      final inProgressStart = dayStart.add(const Duration(hours: 3));
      final items = [
        ...hourlyScheduleItems(dayStart: dayStart, count: 8),
        queueItem(
          id: 'in-progress',
          patientName: 'Active Patient',
          startTime: inProgressStart,
          status: AppointmentStatus.inProgress,
          doctorId: 'd1',
          doctorName: 'Dr Alpha',
          inProgressAt: queueNow.subtract(const Duration(minutes: 15)),
        ),
      ];

      await pumpQueuePage(
        tester,
        viewport: queueWideViewport,
        queueState: AppointmentQueueState(items: items),
        shiftLookup: sampleShiftLookup(),
      );

      final busyInkWell = doctorRowInkWell(tester, 'Dr Alpha');
      final idleInkWell = doctorRowInkWell(tester, 'Dr Beta');
      expect(busyInkWell, isNotNull);
      expect(busyInkWell!.onTap, isNotNull);
      expect(idleInkWell, isNotNull);
      expect(idleInkWell!.onTap, isNull);

      await tester.tap(
        find.descendant(of: find.byType(AppointmentQueueSessionColumn), matching: find.text('Dr Alpha')),
      );
      await tester.pumpAndSettle();

      final activeRect = tester.getRect(find.text('Active Patient').last);
      expect(isRectInViewport(tester, activeRect), isTrue);
    });
  });

  group('FE-008 — Nav badge checked-in count', () {
    testWidgets('queue nav badge shows checked-in count with success tone and updates live', (tester) async {
      final initialState = AppointmentQueueState(
        items: [
          queueItem(id: 'ci-1', patientName: 'One', startTime: dayStart, status: AppointmentStatus.checkedIn),
          queueItem(
            id: 'ci-2',
            patientName: 'Two',
            startTime: dayStart.add(const Duration(hours: 1)),
            status: AppointmentStatus.checkedIn,
          ),
          queueItem(id: 'sched', patientName: 'Three', startTime: dayStart.add(const Duration(hours: 2))),
        ],
      );
      final notifier = MutableQueueNotifier(initialState);

      await pumpQueueWidget(
        tester,
        child: ShellNavSingleItem(item: queueNavItem, isSelected: false, onSelected: (_) {}),
        overrides: [
          ...queueFeWidgetOverrides(
            queueState: initialState,
          ).where((override) => override.origin != appointmentQueueProvider),
          appointmentQueueProvider.overrideWith(() => notifier),
        ],
      );

      expect(find.text('2'), findsOneWidget);
      final badge = tester.widget<Container>(
        find.descendant(of: find.byType(ShellNavBadge), matching: find.byType(Container)),
      );
      expect((badge.decoration! as BoxDecoration).color, ShellTokens.badgeSuccessBackground);

      notifier.replace(
        AppointmentQueueState(
          items: [
            ...initialState.items,
            queueItem(
              id: 'ci-3',
              patientName: 'Four',
              startTime: dayStart.add(const Duration(hours: 3)),
              status: AppointmentStatus.checkedIn,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });
  });

  group('FE-009 — AppNotchedCard action bar sizing', () {
    testWidgets('schedule card actions fit the notch without overflow', (tester) async {
      final items = [queueItem(id: 'a1', patientName: 'Patient', startTime: dayStart)];

      await pumpQueueWidget(
        tester,
        viewport: const Size(360, 600),
        child: AppointmentQueueScheduleColumn(items: items, now: queueNow),
        overrides: [...queueFeWidgetOverrides(queueState: const AppointmentQueueState(items: []))],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Book Appointment'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      expect(find.byType(ClipPath), findsWidgets);
    });
  });

  group('FE-010 — Status journey dialog loading preview', () {
    testWidgets('shows preview timeline while detail loads then transitions in place', (tester) async {
      final item = queueItem(
        id: 'dialog-item',
        patientName: 'Preview Patient',
        startTime: dayStart,
        status: AppointmentStatus.checkedIn,
        checkedInAt: queueNow,
      );
      final detailCompleter = Completer<AppointmentDetail>();

      await pumpQueueWidget(
        tester,
        child: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () => AppointmentStatusJourneyDialog.show(context, item: item),
                child: const Text('Open'),
              ),
            );
          },
        ),
        overrides: [
          ...queueFeWidgetOverrides(queueState: AppointmentQueueState(items: [item])),
          appointmentDetailProvider.overrideWith((ref, appointmentId) async => detailCompleter.future),
        ],
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentStatusJourneyDialog)));

      expect(find.byType(AppointmentStatusTimelineWidget), findsOneWidget);
      expect(find.text('Status journey'), findsOneWidget);
      expect(container.read(appointmentDetailProvider(item.id)).isLoading, isTrue);

      detailCompleter.complete(sampleAppointmentDetail(item));
      await tester.pumpAndSettle();

      expect(find.byType(AppointmentStatusJourneyDialog), findsOneWidget);
      expect(find.text('Status journey'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      final loaded = await container.read(appointmentDetailProvider(item.id).future);
      expect(loaded.notes, 'Loaded from detail RPC');
    });
  });
}
