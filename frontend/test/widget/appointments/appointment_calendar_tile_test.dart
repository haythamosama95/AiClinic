import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
<<<<<<< HEAD
import 'package:syncfusion_flutter_calendar/calendar.dart';
=======
>>>>>>> master

import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_tile.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_tile_context_menu.dart';

import 'calendar_widget_test_harness.dart';

void main() {
  final start = DateTime(2026, 6, 15, 10, 0);
  final end = DateTime(2026, 6, 15, 10, 30);

  Future<void> pumpTile(
    WidgetTester tester, {
    required AppointmentCalendarTile tile,
  }) async {
    await pumpCalendarSurface(
      tester,
      child: Center(child: tile),
      surfaceSize: const Size(800, 200),
    );
    await tester.pump();
  }

  testWidgets('trivial: CAL-TILE-01 renders patient content for appointment item', (tester) async {
    final item = calendarAppointmentItem(patientName: 'Ada Hassan', patientMrn: 'MRN-001');
    await pumpTile(
      tester,
      tile: AppointmentCalendarTile(
        details: calendarTileDetails(
          id: item.id,
          subject: item.patientName,
          start: start,
          end: end,
        ),
        item: item,
        mode: AppointmentCalendarMode.day,
        isDimmed: false,
        onTap: () {},
      ),
    );

    expect(find.textContaining('Ada Hassan'), findsOneWidget);
    expect(find.textContaining('MRN-001'), findsOneWidget);
    expect(find.textContaining('10:00'), findsOneWidget);
  });

  testWidgets('advanced: CAL-TILE-02 onTap fires when tile is tapped', (tester) async {
    var tapped = false;
    final item = calendarAppointmentItem();
    await pumpTile(
      tester,
      tile: AppointmentCalendarTile(
        details: calendarTileDetails(
          id: item.id,
          subject: item.patientName,
          start: start,
          end: end,
        ),
        item: item,
        mode: AppointmentCalendarMode.week,
        isDimmed: false,
        onTap: () => tapped = true,
      ),
    );

    await tester.tap(find.byType(AppointmentCalendarTile));
    expect(tapped, isTrue);
  });

  testWidgets('advanced: CAL-TILE-03 context menu entries invoke callbacks', (tester) async {
    var edited = false;
    var cancelled = false;
    final item = calendarAppointmentItem();
    final entries = appointmentCalendarTileMenuEntries(
      item: item,
      canEdit: true,
      canCancel: true,
      onEdit: () => edited = true,
      onCancel: () => cancelled = true,
    );

    await pumpTile(
      tester,
      tile: AppointmentCalendarTile(
        details: calendarTileDetails(
          id: item.id,
          subject: item.patientName,
          start: start,
          end: end,
          bounds: const Rect.fromLTWH(0, 0, 300, 56),
        ),
        item: item,
        mode: AppointmentCalendarMode.day,
        isDimmed: false,
        onTap: () {},
        contextMenuEntries: entries,
      ),
    );

    expect(find.byType(AppContextMenu), findsOneWidget);

    await tester.longPress(find.byType(AppointmentCalendarTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Edit appointment'), findsOneWidget);
    expect(find.text('Cancel appointment'), findsOneWidget);

    await tester.tap(find.text('Edit appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(edited, isTrue);

    await tester.longPress(find.byType(AppointmentCalendarTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Cancel appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cancelled, isTrue);
  });

  testWidgets('edge case: CAL-TILE-04 null item builds without throwing', (tester) async {
    await pumpTile(
      tester,
      tile: AppointmentCalendarTile(
        details: calendarTileDetails(
          id: 'ghost',
          subject: 'Fallback subject',
          start: start,
          end: end,
        ),
        item: null,
        mode: AppointmentCalendarMode.week,
        isDimmed: false,
        onTap: () {},
      ),
    );

    expect(find.text('Fallback subject'), findsOneWidget);
  });

  testWidgets('trivial: CAL-TILE-05 dimmed and normal tiles both build', (tester) async {
    final item = calendarAppointmentItem(patientName: 'Dim test');
    for (final dimmed in [false, true]) {
      await pumpTile(
        tester,
        tile: AppointmentCalendarTile(
          details: calendarTileDetails(
            id: item.id,
            subject: item.patientName,
            start: start,
            end: end,
          ),
          item: item,
          mode: AppointmentCalendarMode.day,
          isDimmed: dimmed,
          onTap: () {},
        ),
      );
      expect(find.textContaining('Dim test'), findsOneWidget);
    }
  });
}
