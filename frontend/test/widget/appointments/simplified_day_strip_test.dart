import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_day_strip.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimplifiedDayStrip', () {
    final reference = DateTime(2026, 6, 27);

    Future<void> pumpStrip(
      WidgetTester tester, {
      required DateTime selectedDate,
      required ValueChanged<DateTime> onDateSelected,
    }) async {
      await withClock(Clock.fixed(reference), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: Scaffold(
              body: SimplifiedDayStrip(selectedDate: selectedDate, onDateSelected: onDateSelected),
            ),
          ),
        );
      });
      await tester.pumpAndSettle();
    }

    testWidgets('centers selected day in visible strip', (tester) async {
      final midDate = DateTime(2026, 7, 4);
      await pumpStrip(tester, selectedDate: midDate, onDateSelected: (_) {});

      expect(find.text('${midDate.day}'), findsOneWidget);
      expect(find.text('${midDate.subtract(const Duration(days: 1)).day}'), findsOneWidget);
      expect(find.text('${midDate.add(const Duration(days: 1)).day}'), findsOneWidget);
    });

    testWidgets('chevron right advances within 90-day window', (tester) async {
      DateTime? selected;
      await pumpStrip(tester, selectedDate: reference, onDateSelected: (date) => selected = date);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      expect(selected, DateTime(2026, 6, 28));
    });

    testWidgets('chevron left is disabled on today', (tester) async {
      await pumpStrip(tester, selectedDate: reference, onDateSelected: (_) {});

      final backButton = tester.widgetList<IconButton>(find.byType(IconButton)).first;
      expect(backButton.onPressed, isNull);
    });

    testWidgets('clamps selection at today+90', (tester) async {
      final maxDate = DateTime(2026, 9, 25);
      DateTime? selected;
      await pumpStrip(tester, selectedDate: maxDate, onDateSelected: (date) => selected = date);

      final forwardButton = tester.widgetList<IconButton>(find.byType(IconButton)).last;
      expect(forwardButton.onPressed, isNull);

      await tester.tap(find.text('${maxDate.day}'));
      await tester.pumpAndSettle();
      expect(selected, maxDate);
    });
  });
}
