import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_time_block_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  String slotLabel(int hour) => DateFormat.Hm().format(DateTime(2026, 6, 27, hour));

  SimplifiedBookingSlot slot({
    required int hour,
    required SlotAvailabilityState state,
    List<String> doctorIds = const [],
  }) {
    final start = DateTime(2026, 6, 27, hour);
    return SimplifiedBookingSlot(
      startTime: start,
      endTime: start.add(const Duration(minutes: 30)),
      state: state,
      availableDoctorIds: doctorIds,
    );
  }

  group('SimplifiedTimeBlockGrid', () {
    Future<void> pumpGrid(
      WidgetTester tester, {
      required List<SimplifiedBookingSlot> slots,
      DateTime? selectedStart,
      ValueChanged<SimplifiedBookingSlot>? onSlotTap,
      ValueChanged<SimplifiedBookingSlot>? onAlternateSlotTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Scaffold(
            body: SimplifiedTimeBlockGrid(
              slots: slots,
              selectedStart: selectedStart,
              onSlotTap: onSlotTap ?? (_) {},
              onAlternateSlotTap: onAlternateSlotTap,
              collapsedSlotCount: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders available, alternate, and unavailable states', (tester) async {
      await pumpGrid(
        tester,
        slots: [
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, doctorIds: ['doctor-b']),
          slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable),
          slot(hour: 12, state: SlotAvailabilityState.past),
        ],
      );

      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
      expect(find.text(slotLabel(9)), findsOneWidget);
    });

    testWidgets('selects available block and highlights selection', (tester) async {
      final available = slot(hour: 9, state: SlotAvailabilityState.available);
      SimplifiedBookingSlot? tapped;

      await pumpGrid(
        tester,
        slots: [available],
        selectedStart: available.startTime,
        onSlotTap: (value) => tapped = value,
      );

      await tester.tap(find.text(slotLabel(9)));
      await tester.pumpAndSettle();

      expect(tapped, available);
      expect(tester.getSemantics(find.text(slotLabel(9))).label, contains('selected'));
    });

    testWidgets('routes alternate taps and ignores unavailable blocks', (tester) async {
      final alternate = slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, doctorIds: ['doctor-b']);
      final unavailable = slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable);
      SimplifiedBookingSlot? alternateTapped;
      var availableTapped = false;

      await pumpGrid(
        tester,
        slots: [alternate, unavailable],
        onSlotTap: (_) => availableTapped = true,
        onAlternateSlotTap: (value) => alternateTapped = value,
      );

      await tester.tap(find.text(slotLabel(11)));
      await tester.pumpAndSettle();
      expect(availableTapped, isFalse);

      await tester.tap(find.text(slotLabel(10)));
      await tester.pumpAndSettle();
      expect(alternateTapped, alternate);
    });

    testWidgets('show more expands hidden slots with available count', (tester) async {
      await pumpGrid(
        tester,
        slots: [
          slot(hour: 8, state: SlotAvailabilityState.available),
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.fullyUnavailable),
          slot(hour: 11, state: SlotAvailabilityState.available),
          slot(hour: 12, state: SlotAvailabilityState.available),
        ],
      );

      expect(find.text('Show more slots'), findsOneWidget);
      expect(find.text('4 available'), findsOneWidget);
      expect(find.text(slotLabel(12)), findsNothing);

      await tester.tap(find.byKey(const Key('simplified_time_block_show_more')));
      await tester.pumpAndSettle();

      expect(find.text(slotLabel(12)), findsOneWidget);
      expect(find.text('Show more slots'), findsNothing);
    });
  });
}
