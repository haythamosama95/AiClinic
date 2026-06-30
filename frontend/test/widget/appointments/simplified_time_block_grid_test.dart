import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/alternate_doctors_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_chip_style.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_time_block_grid.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  String slotLabel(int hour) => DateFormat.jm().format(DateTime(2026, 6, 27, hour));

  SimplifiedBookingSlot slot({
    required int hour,
    required SlotAvailabilityState state,
    List<String> doctorIds = const [],
    int durationMinutes = 30,
  }) {
    final start = DateTime(2026, 6, 27, hour);
    return SimplifiedBookingSlot(
      startTime: start,
      endTime: start.add(Duration(minutes: durationMinutes)),
      state: state,
      availableDoctorIds: doctorIds,
    );
  }

  const testDoctors = [
    StaffListItem(id: 'doctor-a', fullName: 'Dr. Ada', role: StaffRole.doctor, isActive: true),
    StaffListItem(id: 'doctor-b', fullName: 'Dr. Ben', role: StaffRole.doctor, isActive: true),
  ];

  group('SimplifiedTimeBlockGrid', () {
    Future<void> pumpGrid(
      WidgetTester tester, {
      required List<SimplifiedBookingSlot> slots,
      DateTime? selectedStart,
      bool hideFullyBooked = false,
      int collapsedSlotCount = 4,
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
              collapsedSlotCount: collapsedSlotCount,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpGridWithDoctorDialog(
      WidgetTester tester, {
      required List<SimplifiedBookingSlot> slots,
      bool hasPreferredDoctor = true,
      List<StaffListItem> doctors = testDoctors,
      ValueChanged<SimplifiedBookingSlot>? onSlotTap,
      ValueChanged<SimplifiedBookingSlot>? onAlternateSlotTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              Future<void> showDialog(SimplifiedBookingSlot tappedSlot) {
                return AlternateDoctorsDialog.show(
                  context,
                  slot: tappedSlot,
                  doctors: doctors,
                  hasPreferredDoctor: hasPreferredDoctor,
                  onDoctorSelected: (_) {},
                );
              }

              return Scaffold(
                body: SimplifiedTimeBlockGrid(
                  slots: slots,
                  onSlotTap: onSlotTap ?? showDialog,
                  onAlternateSlotTap: onAlternateSlotTap ?? showDialog,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('FE-E01 available tap selects block', (tester) async {
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

    testWidgets('FE-E02 past block tap is a no-op', (tester) async {
      var tapped = false;

      await pumpGrid(
        tester,
        slots: [slot(hour: 7, state: SlotAvailabilityState.past)],
        onSlotTap: (_) => tapped = true,
      );

      await tester.tap(find.text(slotLabel(7)));
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    });

    testWidgets('FE-E03 fully booked block tap is a no-op', (tester) async {
      var tapped = false;

      await pumpGrid(
        tester,
        slots: [slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable)],
        onSlotTap: (_) => tapped = true,
      );

      await tester.tap(find.text(slotLabel(11)));
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    });

    testWidgets('FE-E04 alternate block tap opens AlternateDoctorsDialog', (tester) async {
      final alternate = slot(
        hour: 10,
        state: SlotAvailabilityState.alternateDoctorsAvailable,
        doctorIds: ['doctor-b'],
      );

      await pumpGridWithDoctorDialog(
        tester,
        slots: [alternate],
        hasPreferredDoctor: true,
      );

      await tester.tap(find.text(slotLabel(10)));
      await tester.pumpAndSettle();

      expect(find.text('Other doctors available'), findsOneWidget);
      expect(find.text('Dr. Ben'), findsOneWidget);
    });

    testWidgets('FE-E05 alternate block shows distinct semi-available styling', (tester) async {
      await pumpGrid(
        tester,
        slots: [
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, doctorIds: ['doctor-b']),
          slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable),
        ],
      );

      final colors = tester.element(find.byKey(const Key('simplified_time_block_grid'))).semanticColors;
      final alternateStyle = SimplifiedSlotChipStyle.forState(colors, SlotAvailabilityState.alternateDoctorsAvailable);

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      final alternateChip = find.ancestor(
        of: find.text(slotLabel(10)),
        matching: find.byType(Material),
      );
      final alternateMaterial = tester.widget<Material>(alternateChip.first);
      expect(alternateMaterial.color, alternateStyle.background);
    });

    testWidgets('FE-E06 selected available block uses primary fill and white text', (tester) async {
      final available = slot(hour: 9, state: SlotAvailabilityState.available);

      await pumpGrid(
        tester,
        slots: [available],
        selectedStart: available.startTime,
      );

      final colors = tester.element(find.text(slotLabel(9))).semanticColors;
      final selectedChip = find.ancestor(
        of: find.text(slotLabel(9)),
        matching: find.byType(Material),
      );
      final material = tester.widget<Material>(selectedChip.first);
      final text = tester.widget<Text>(find.text(slotLabel(9)));

      expect(material.color, colors.primary);
      expect(text.style?.color, colors.primaryForeground);
    });

    testWidgets('FE-E07 empty day shows no slots message', (tester) async {
      await pumpGrid(tester, slots: const []);

      expect(find.text('No slots available for this day.'), findsOneWidget);
    });

    testWidgets('FE-E08 hide fully booked leaves no bookable slots message', (tester) async {
      await pumpGrid(
        tester,
        hideFullyBooked: true,
        slots: [slot(hour: 10, state: SlotAvailabilityState.fullyUnavailable)],
      );

      expect(find.text('No bookable slots for this day.'), findsOneWidget);
    });

    testWidgets('FE-E09 grid scroll reveals slots beyond collapsed viewport', (tester) async {
      await pumpGrid(
        tester,
        collapsedSlotCount: 8,
        slots: [
          for (var hour = 8; hour < 18; hour++)
            slot(hour: hour, state: SlotAvailabilityState.available),
        ],
      );

      expect(find.text(slotLabel(17)), findsNothing);

      final grid = find.byKey(const Key('simplified_time_block_grid'));
      await tester.drag(grid, const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(find.text(slotLabel(17)), findsOneWidget);
    });

    testWidgets('FE-E10 semantics labels include time and availability state', (tester) async {
      await pumpGrid(
        tester,
        slots: [
          slot(hour: 9, state: SlotAvailabilityState.available),
          slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, doctorIds: ['doctor-b']),
          slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable),
          slot(hour: 12, state: SlotAvailabilityState.past),
        ],
      );

      final gridFinder = find.byKey(const Key('simplified_time_block_grid'));

      final availableFinder = find.descendant(
        of: gridFinder,
        matching: find.text(slotLabel(9)),
      );
      expect(availableFinder, findsOneWidget);
      final availableSemantics = tester.getSemantics(availableFinder);
      expect(availableSemantics.label.split('\n').first, '${slotLabel(9)}, available');

      final alternateFinder = find.descendant(
        of: gridFinder,
        matching: find.text(slotLabel(10)),
      );
      expect(alternateFinder, findsOneWidget);
      final alternateSemantics = tester.getSemantics(alternateFinder);
      expect(alternateSemantics.label.split('\n').first, '${slotLabel(10)}, other doctors available');

      final fullyBookedFinder = find.descendant(
        of: gridFinder,
        matching: find.text(slotLabel(11)),
      );
      expect(fullyBookedFinder, findsOneWidget);
      final fullyBookedSemantics = tester.getSemantics(fullyBookedFinder);
      expect(fullyBookedSemantics.label.split('\n').first, '${slotLabel(11)}, fully booked');

      final pastFinder = find.descendant(
        of: gridFinder,
        matching: find.text(slotLabel(12)),
      );
      expect(pastFinder, findsOneWidget);
      final pastSemantics = tester.getSemantics(pastFinder);
      expect(pastSemantics.label.split('\n').first, '${slotLabel(12)}, past');
    });

    testWidgets('FE-E11 each block spans the default 30-minute duration', (tester) async {
      const durationMinutes = 30;
      final slots = [
        slot(hour: 9, state: SlotAvailabilityState.available, durationMinutes: durationMinutes),
        slot(hour: 10, state: SlotAvailabilityState.alternateDoctorsAvailable, durationMinutes: durationMinutes),
        slot(hour: 11, state: SlotAvailabilityState.fullyUnavailable, durationMinutes: durationMinutes),
      ];

      await pumpGrid(tester, slots: slots);

      for (final block in slots) {
        expect(block.endTime.difference(block.startTime).inMinutes, durationMinutes);
      }
    });

    testWidgets('FE-E14 available tap opens doctor picker without preferred doctor', (tester) async {
      final available = slot(
        hour: 9,
        state: SlotAvailabilityState.available,
        doctorIds: ['doctor-a', 'doctor-b'],
      );

      await pumpGridWithDoctorDialog(
        tester,
        slots: [available],
        hasPreferredDoctor: false,
      );

      await tester.tap(find.text(slotLabel(9)));
      await tester.pumpAndSettle();

      expect(find.text('Select a doctor'), findsOneWidget);
      expect(find.textContaining('Select a doctor for'), findsOneWidget);
      expect(find.text('Dr. Ada'), findsOneWidget);
      expect(find.text('Dr. Ben'), findsOneWidget);
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
