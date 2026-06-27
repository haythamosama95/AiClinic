import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('SimplifiedSlotSummaryCard', () {
    final selectedSlot = SimplifiedBookingSlot(
      startTime: DateTime(2026, 6, 27, 10),
      endTime: DateTime(2026, 6, 27, 10, 30),
      state: SlotAvailabilityState.available,
      availableDoctorIds: const ['doctor-a'],
    );

    Future<void> pumpCard(
      WidgetTester tester, {
      required AppointmentRpcTestClient client,
      SimplifiedBookingSlot? slot,
      bool slotsAvailable = true,
      VoidCallback? onRetry,
      VoidCallback? onSlotsRefresh,
      VoidCallback? onBookingComplete,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: Scaffold(
              body: SimplifiedSlotSummaryCard(
                branchId: 'branch-a',
                patientId: 'patient-a',
                effectiveDoctorId: 'doctor-a',
                defaultDurationMinutes: 30,
                doctorName: 'Dr. Ada',
                selectedDate: DateTime(2026, 6, 27),
                selectedSlot: slot,
                slotsAvailable: slotsAvailable,
                onRetry: onRetry,
                onSlotsRefresh: onSlotsRefresh ?? () {},
                onBookingComplete: onBookingComplete,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows placeholder and disables confirm without selection', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client);

      expect(find.text('Select a time slot above'), findsOneWidget);
      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('shows formatted selection and enables confirm', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client, slot: selectedSlot);

      final weekday = DateFormat.EEEE().format(DateTime(2026, 6, 27));
      expect(find.textContaining('$weekday, Jun 27'), findsOneWidget);
      expect(find.text('Dr. Ada'), findsOneWidget);

      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('creates appointment on confirm', (tester) async {
      final client = AppointmentRpcTestClient();
      var completed = false;

      await pumpCard(tester, client: client, slot: selectedSlot, onBookingComplete: () => completed = true);

      await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
      expect(client.createAppointmentCalls.single['p_doctor_id'], 'doctor-a');
      expect(client.createAppointmentCalls.single['p_duration_minutes'], 30);
      expect(completed, isTrue);
    });

    testWidgets('blocks confirm and shows retry when slots unavailable', (tester) async {
      final client = AppointmentRpcTestClient();
      var retried = false;

      await pumpCard(tester, client: client, slot: selectedSlot, slotsAvailable: false, onRetry: () => retried = true);

      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNull);
      expect(find.textContaining('Could not load available slots'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, isTrue);
    });

    testWidgets('refreshes slots on schedule conflict', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'SCHEDULE_CONFLICT',
          'error_message': 'Overlap',
        };
      var refreshed = false;

      await pumpCard(tester, client: client, slot: selectedSlot, onSlotsRefresh: () => refreshed = true);

      await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
      await tester.pumpAndSettle();

      expect(refreshed, isTrue);
      expect(find.textContaining('overlaps another booked slot'), findsOneWidget);
      expect(client.createAppointmentCalls, hasLength(1));
    });
  });
}
