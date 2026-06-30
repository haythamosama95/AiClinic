import 'dart:ui' show Tristate;

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_day_strip.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('SimplifiedDayStrip', () {
    final reference = DateTime(2026, 6, 27);
    final maxDate = simplifiedBookingDateRange(reference: reference).maxDate;

    Finder dayStripButton(String tooltip) {
      return find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton));
    }

    Future<T> withReferenceClock<T>(Future<T> Function() body) {
      return withClock(Clock.fixed(reference), body);
    }

    Future<void> pumpStrip(
      WidgetTester tester, {
      required DateTime selectedDate,
      required ValueChanged<DateTime> onDateSelected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Scaffold(
            body: SimplifiedDayStrip(selectedDate: selectedDate, onDateSelected: onDateSelected),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('FE-F01 centered selection shows selected day in window center', (tester) async {
      await withReferenceClock(() async {
        final midDate = DateTime(2026, 7, 4);
        await pumpStrip(tester, selectedDate: midDate, onDateSelected: (_) {});

        for (final offset in [-3, -2, -1, 0, 1, 2, 3]) {
          final day = midDate.add(Duration(days: offset));
          expect(find.text('${day.day}'), findsOneWidget);
        }

        expect(find.text('${midDate.subtract(const Duration(days: 4)).day}'), findsNothing);
        expect(find.text('${midDate.add(const Duration(days: 4)).day}'), findsNothing);
      });
    });

    testWidgets('FE-F02 chevron prev selects previous day', (tester) async {
      await withReferenceClock(() async {
        final startDate = reference.add(const Duration(days: 1));
        DateTime? selected;
        await pumpStrip(tester, selectedDate: startDate, onDateSelected: (date) => selected = date);

        await tester.ensureVisible(dayStripButton('Previous day'));
        await tester.tap(dayStripButton('Previous day'));
        await tester.pumpAndSettle();

        expect(selected, reference);
      });
    });

    testWidgets('FE-F03 chevron next selects next day', (tester) async {
      await withReferenceClock(() async {
        DateTime? selected;
        await pumpStrip(tester, selectedDate: reference, onDateSelected: (date) => selected = date);

        await tester.ensureVisible(dayStripButton('Next day'));
        await tester.tap(dayStripButton('Next day'));
        await tester.pumpAndSettle();

        expect(selected, reference.add(const Duration(days: 1)));
      });
    });

    testWidgets('FE-F04 direct day tap updates selected date', (tester) async {
      await withReferenceClock(() async {
        final tappedDate = reference.add(const Duration(days: 3));
        DateTime? selected;
        await pumpStrip(tester, selectedDate: reference, onDateSelected: (date) => selected = date);

        await tester.tap(find.text('${tappedDate.day}'));
        await tester.pumpAndSettle();

        expect(selected, tappedDate);
      });
    });

    testWidgets('FE-F05 selected day uses bold underline and primary color', (tester) async {
      await withReferenceClock(() async {
        final selectedDate = DateTime(2026, 7, 4);
        await pumpStrip(tester, selectedDate: selectedDate, onDateSelected: (_) {});

        final colors = tester.element(find.byType(SimplifiedDayStrip)).semanticColors;
        final stripFinder = find.byType(SimplifiedDayStrip);

        final dayNumberFinder = find.descendant(of: stripFinder, matching: find.text('${selectedDate.day}'));
        expect(dayNumberFinder, findsOneWidget);
        final dayStyle = tester.widget<Text>(dayNumberFinder).style!;
        expect(dayStyle.fontWeight, FontWeight.w800);
        expect(dayStyle.decoration, TextDecoration.underline);
        expect(dayStyle.color, colors.primary);

        final weekdayLabel = DateFormat.E().format(selectedDate);
        final weekdayFinder = find.descendant(of: stripFinder, matching: find.text(weekdayLabel));
        expect(weekdayFinder, findsOneWidget);
        final weekdayStyle = tester.widget<Text>(weekdayFinder).style!;
        expect(weekdayStyle.fontWeight, FontWeight.w700);
        expect(weekdayStyle.color, colors.primary);
      });
    });

    testWidgets('FE-F06 window at min edge excludes dates before today', (tester) async {
      await withReferenceClock(() async {
        await pumpStrip(tester, selectedDate: reference, onDateSelected: (_) {});

        final backButton = tester.widgetList<IconButton>(find.byType(IconButton)).first;
        expect(backButton.onPressed, isNull);

        expect(find.text('${reference.subtract(const Duration(days: 1)).day}'), findsNothing);

        for (final offset in [0, 1, 2, 3, 4, 5, 6]) {
          final day = reference.add(Duration(days: offset));
          expect(find.text('${day.day}'), findsOneWidget);
        }
      });
    });

    testWidgets('FE-F07 window at max edge excludes dates beyond today+90', (tester) async {
      await withReferenceClock(() async {
        await pumpStrip(tester, selectedDate: maxDate, onDateSelected: (_) {});

        final forwardButton = tester.widgetList<IconButton>(find.byType(IconButton)).last;
        expect(forwardButton.onPressed, isNull);

        expect(find.text('${maxDate.add(const Duration(days: 1)).day}'), findsNothing);

        for (final offset in [-6, -5, -4, -3, -2, -1, 0]) {
          final day = maxDate.add(Duration(days: offset));
          expect(find.text('${day.day}'), findsOneWidget);
        }
      });
    });

    testWidgets('FE-F08 semantics announce full date label', (tester) async {
      await withReferenceClock(() async {
        final selectedDate = DateTime(2026, 7, 4);
        final neighborDate = selectedDate.subtract(const Duration(days: 1));

        await pumpStrip(tester, selectedDate: selectedDate, onDateSelected: (_) {});

        final stripFinder = find.byType(SimplifiedDayStrip);
        final selectedLabel = DateFormat.yMMMMd().format(selectedDate);
        final selectedDayFinder = find.descendant(of: stripFinder, matching: find.text('${selectedDate.day}'));
        expect(selectedDayFinder, findsOneWidget);
        final selectedSemantics = tester.getSemantics(selectedDayFinder);
        expect(selectedSemantics.label.split('\n').first, 'Selected, $selectedLabel');
        expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);

        final neighborLabel = DateFormat.yMMMMd().format(neighborDate);
        final neighborDayFinder = find.descendant(of: stripFinder, matching: find.text('${neighborDate.day}'));
        expect(neighborDayFinder, findsOneWidget);
        final neighborSemantics = tester.getSemantics(neighborDayFinder);
        expect(neighborSemantics.label.split('\n').first, neighborLabel);
      });
    });
  });
}
