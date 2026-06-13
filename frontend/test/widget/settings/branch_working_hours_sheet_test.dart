import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_working_hours_sheet.dart';

void main() {
  group('BranchWorkingHoursSheet', () {
    BranchWorkingSchedule scheduleWithMonday({required String openTime, required String closeTime}) {
      return BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => day == BranchWeekday.monday
                  ? BranchWorkingDayHours(day: day, isWorkingDay: true, openTime: openTime, closeTime: closeTime)
                  : BranchWorkingDayHours(day: day, isWorkingDay: false),
            )
            .toList(growable: false),
      );
    }

    Future<void> pumpSheet(
      WidgetTester tester, {
      required BranchWorkingSchedule initialSchedule,
      bool startInEditMode = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: BranchWorkingHoursSheet(
              initialSchedule: initialSchedule,
              startInEditMode: startInEditMode,
              confirmLabel: 'Save',
              onUpdate: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows error panel when close time is before open time', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '17:00', closeTime: '09:00'),
      );

      expect(find.text('Close time must be after open time.'), findsOneWidget);
      expect(find.byType(AppAlert), findsOneWidget);
    });

    testWidgets('shows error panel when close time equals open time', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '09:00', closeTime: '09:00'),
      );

      expect(find.text('Close time must be after open time.'), findsOneWidget);
      expect(find.byType(AppAlert), findsOneWidget);
    });

    testWidgets('does not show time range error panel for valid hours', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '09:00', closeTime: '17:00'),
      );

      expect(find.text('Close time must be after open time.'), findsNothing);
      expect(find.byType(AppAlert), findsNothing);
    });

    testWidgets('toggle day off clears times', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '09:00', closeTime: '17:00'),
      );

      final mondaySwitch = find.descendant(
        of: find.ancestor(of: find.text('Monday'), matching: find.byType(Row)).first,
        matching: find.byType(FSwitch),
      );
      await tester.tap(mondaySwitch);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppClockTimeField, 'From'), findsNothing);
    });

    testWidgets('all days off rejected on save', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '09:00', closeTime: '17:00'),
      );

      final mondaySwitch = find.descendant(
        of: find.ancestor(of: find.text('Monday'), matching: find.byType(Row)).first,
        matching: find.byType(FSwitch),
      );
      await tester.tap(mondaySwitch);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('At least one working day is required.'), findsOneWidget);
    });

    testWidgets('midnight-spanning hours rejected', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '22:00', closeTime: '06:00'),
      );

      expect(find.text('Close time must be after open time.'), findsOneWidget);
    });

    testWidgets('stupid usage: spam toggle all days', (tester) async {
      await pumpSheet(
        tester,
        initialSchedule: scheduleWithMonday(openTime: '09:00', closeTime: '17:00'),
      );

      for (final day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) {
        final daySwitch = find.descendant(
          of: find.ancestor(of: find.text(day), matching: find.byType(Row)).first,
          matching: find.byType(FSwitch),
        );
        if (daySwitch.evaluate().isNotEmpty) {
          await tester.tap(daySwitch);
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
