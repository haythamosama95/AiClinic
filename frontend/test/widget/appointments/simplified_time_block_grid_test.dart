import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_time_block_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  String slotLabel(int hour) => DateFormat.jm().format(DateTime(2026, 6, 27, hour));

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
      bool hideFullyBooked = false,
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
              hideFullyBooked: hideFullyBooked,
              onSlotTap: onSlotTap ?? (_) {},
              onAlternateSlotTap: onAlternateSlotTap,
              collapsedSlotCount: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders available, alternate hint, and fully booked states', (tester) async {
      await pumpGrid(
        tester,
        slots: [
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, doctorIds: ['doctor-b']),
          slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable),
          slot(hour: 12, state: SlotAvailabilityState.past),
        ],
      );

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      expect(find.text(slotLabel(9)), findsOneWidget);
    });

    testWidgets('hides fully booked slots when toggle is on', (tester) async {
      await pumpGrid(
        tester,
        hideFullyBooked: true,
        slots: [
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.fullyUnavailable),
        ],
      );

      expect(find.text(slotLabel(9)), findsOneWidget);
      expect(find.text(slotLabel(10)), findsNothing);
    });

    testWidgets('animates when fully booked slots are hidden', (tester) async {
      final slots = [
        slot(hour: 9, state: SlotAvailabilityState.available),
        slot(hour: 10, state: SlotAvailabilityState.fullyUnavailable),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: _HideFullyBookedHarness(slots: slots),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(slotLabel(10)), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_hide_fully_booked')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text(slotLabel(10)), findsNothing);
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

    testWidgets('scroll reveals hidden slots when grid overflows', (tester) async {
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

      expect(find.text(slotLabel(12)), findsNothing);

      final grid = find.byKey(const Key('simplified_time_block_grid'));
      await tester.drag(grid, const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(find.text(slotLabel(12)), findsOneWidget);
    });
  });
}

class _HideFullyBookedHarness extends StatefulWidget {
  const _HideFullyBookedHarness({required this.slots});

  final List<SimplifiedBookingSlot> slots;

  @override
  State<_HideFullyBookedHarness> createState() => _HideFullyBookedHarnessState();
}

class _HideFullyBookedHarnessState extends State<_HideFullyBookedHarness> {
  var _hideFullyBooked = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Switch(
            key: const Key('toggle_hide_fully_booked'),
            value: _hideFullyBooked,
            onChanged: (value) => setState(() => _hideFullyBooked = value),
          ),
          SimplifiedTimeBlockGrid(slots: widget.slots, hideFullyBooked: _hideFullyBooked, onSlotTap: (_) {}),
        ],
      ),
    );
  }
}
