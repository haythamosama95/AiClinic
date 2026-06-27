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

    testWidgets('lists only available doctors and selects on tap', (tester) async {
      String? selectedDoctorId;

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
                        onDoctorSelected: (doctorId) => selectedDoctorId = doctorId,
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

      expect(find.text('Dr. Ada'), findsOneWidget);
      expect(find.text('Dr. Ben'), findsNothing);
      expect(find.textContaining('10:00'), findsOneWidget);

      await tester.tap(find.text('Dr. Ada'));
      await tester.pumpAndSettle();

      expect(selectedDoctorId, 'doctor-a');
      expect(find.text('Other doctors available'), findsNothing);
    });

    testWidgets('cancel dismisses without selecting', (tester) async {
      var selected = false;

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
                        onDoctorSelected: (_) => selected = true,
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selected, isFalse);
    });
  });
}
