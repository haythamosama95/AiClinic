import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/alternate_doctors_dialog.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlternateDoctorsDialog', () {
    final slot = SimplifiedBookingSlot(
      startTime: DateTime(2026, 6, 27, 10),
      endTime: DateTime(2026, 6, 27, 10, 30),
      state: SlotAvailabilityState.alternateDoctorsAvailable,
      availableDoctorIds: const ['doctor-a'],
    );

    const doctors = [
      StaffListItem(id: 'doctor-a', fullName: 'Dr. Ada', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: 'doctor-b', fullName: 'Dr. Ben', role: StaffRole.doctor, isActive: true),
    ];

    Future<void> openDialog(
      WidgetTester tester, {
      required SimplifiedBookingSlot slot,
      required List<StaffListItem> doctors,
      required ValueChanged<String> onDoctorSelected,
      bool hasPreferredDoctor = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      AlternateDoctorsDialog.show(
                        context,
                        slot: slot,
                        doctors: doctors,
                        hasPreferredDoctor: hasPreferredDoctor,
                        onDoctorSelected: onDoctorSelected,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('FUNC-G01: lists only availableDoctorIds doctors', (tester) async {
      await openDialog(
        tester,
        slot: slot,
        doctors: doctors,
        onDoctorSelected: (_) {},
      );

      expect(find.text('Dr. Ada'), findsOneWidget);
      expect(find.text('Dr. Ben'), findsNothing);
      expect(find.textContaining('10:00'), findsOneWidget);
    });

    testWidgets('FUNC-G02: tap doctor closes dialog and invokes onDoctorSelected', (tester) async {
      String? selectedDoctorId;

      await openDialog(
        tester,
        slot: slot,
        doctors: doctors,
        onDoctorSelected: (doctorId) => selectedDoctorId = doctorId,
      );

      await tester.tap(find.text('Dr. Ada'));
      await tester.pumpAndSettle();

      expect(selectedDoctorId, 'doctor-a');
      expect(find.text('Other doctors available'), findsNothing);
    });

    testWidgets('FUNC-G03: cancel dismisses without selecting', (tester) async {
      var selected = false;

      await openDialog(
        tester,
        slot: slot,
        doctors: doctors,
        onDoctorSelected: (_) => selected = true,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selected, isFalse);
      expect(find.text('Other doctors available'), findsNothing);
    });

    testWidgets('FUNC-G04: empty availableDoctorIds shows empty message', (tester) async {
      final emptySlot = SimplifiedBookingSlot(
        startTime: DateTime(2026, 6, 27, 10),
        endTime: DateTime(2026, 6, 27, 10, 30),
        state: SlotAvailabilityState.alternateDoctorsAvailable,
        availableDoctorIds: [],
      );

      await openDialog(
        tester,
        slot: emptySlot,
        doctors: doctors,
        onDoctorSelected: (_) {},
      );

      expect(find.text('Dr. Ada'), findsNothing);
      expect(find.text('Dr. Ben'), findsNothing);
      expect(find.text('No alternate doctors are available.'), findsOneWidget);
    });

    testWidgets('FUNC-G05: without preferred doctor shows Select a doctor title', (tester) async {
      await openDialog(
        tester,
        slot: slot,
        doctors: doctors,
        hasPreferredDoctor: false,
        onDoctorSelected: (_) {},
      );

      expect(find.text('Select a doctor'), findsOneWidget);
      expect(find.textContaining('Select a doctor for'), findsOneWidget);
      expect(find.text('Other doctors available'), findsNothing);
      expect(find.textContaining('Other doctors are available'), findsNothing);
    });

    testWidgets('FUNC-G06: doctors sorted by full name', (tester) async {
      final multiAlternateSlot = SimplifiedBookingSlot(
        startTime: DateTime(2026, 6, 27, 10),
        endTime: DateTime(2026, 6, 27, 10, 30),
        state: SlotAvailabilityState.alternateDoctorsAvailable,
        availableDoctorIds: ['doctor-b', 'doctor-a'],
      );

      await openDialog(
        tester,
        slot: multiAlternateSlot,
        doctors: doctors,
        onDoctorSelected: (_) {},
      );

      expect(find.text('Dr. Ada'), findsOneWidget);
      expect(find.text('Dr. Ben'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Dr. Ada')).dy,
        lessThan(tester.getTopLeft(find.text('Dr. Ben')).dy),
      );
    });

    testWidgets('FUNC-G07: barrier tap dismisses without selecting', (tester) async {
      var selected = false;

      await openDialog(
        tester,
        slot: slot,
        doctors: doctors,
        onDoctorSelected: (_) => selected = true,
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(selected, isFalse);
      expect(find.text('Other doctors available'), findsNothing);
    });
  });
}
