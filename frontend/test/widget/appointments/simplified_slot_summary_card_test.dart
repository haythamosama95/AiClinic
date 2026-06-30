import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';

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
      String effectiveDoctorId = 'doctor-a',
      String doctorName = 'Dr. Ada',
      String? notes,
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
                effectiveDoctorId: effectiveDoctorId,
                defaultDurationMinutes: 30,
                doctorName: doctorName,
                selectedDate: DateTime(2026, 6, 27),
                selectedSlot: slot,
                notes: notes,
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

    testWidgets('FUNC-H01: no selection shows placeholder and disables confirm', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client);

      expect(find.text('Select a time slot above'), findsOneWidget);
      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('FUNC-H02: selection label shows weekday date and time range', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client, slot: selectedSlot);

      final weekday = DateFormat.EEEE().format(DateTime(2026, 6, 27));
      final monthDay = DateFormat.MMMd().format(DateTime(2026, 6, 27));
      final from = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
      final to = DateFormat.jm().format(DateTime(2026, 6, 27, 10, 30));

      expect(find.textContaining('$weekday, $monthDay'), findsOneWidget);
      expect(find.textContaining('$from – $to'), findsOneWidget);
    });

    testWidgets('FUNC-H03: doctor name shown below selected time', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client, slot: selectedSlot, doctorName: 'Dr. Ada');

      expect(find.text('Dr. Ada'), findsOneWidget);
    });

    testWidgets('FUNC-H04: happy path confirm creates appointment and completes booking', (tester) async {
      final client = AppointmentRpcTestClient();
      var completed = false;

      await pumpCard(tester, client: client, slot: selectedSlot, onBookingComplete: () => completed = true);

      await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
      expect(completed, isTrue);
    });

    testWidgets('FUNC-H05: confirm uses default duration and planned type', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpCard(tester, client: client, slot: selectedSlot);

      await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
      await tester.pumpAndSettle();

      final call = client.createAppointmentCalls.single;
      expect(call['p_duration_minutes'], 30);
      expect(call['p_type'], 'planned');
    });

    testWidgets('FUNC-H06: confirm passes step-one notes to create_appointment', (tester) async {
      final client = AppointmentRpcTestClient();
      const notes = 'Patient prefers morning visits';

      await pumpCard(tester, client: client, slot: selectedSlot, notes: notes);

      await tester.tap(find.byKey(const Key('simplified_slot_confirm')));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls.single['p_notes'], notes);
    });

    testWidgets('FUNC-H07: schedule conflict refreshes slots and shows overlap message', (tester) async {
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

    testWidgets('FUNC-H08: no effectiveDoctorId disables confirm', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpCard(tester, client: client, slot: selectedSlot, effectiveDoctorId: '', doctorName: '');

      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('FUNC-H08 bug-fix: no effectiveDoctorId shows blocked confirm message', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpCard(tester, client: client, slot: selectedSlot, effectiveDoctorId: '', doctorName: '');

      expect(find.text('Select a doctor for this time slot before confirming.'), findsOneWidget);
    });

    /// Flushes Forui [FTappable] press/release animation timers (100 ms each).
    Future<void> tapForuiControl(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    testWidgets('FUNC-H09: double confirm creates only one appointment', (tester) async {
      final client = SlowCreateAppointmentRpcClient();

      await pumpCard(tester, client: client, slot: selectedSlot);

      final confirmFinder = find.byKey(const Key('simplified_slot_confirm'));
      await tapForuiControl(tester, confirmFinder);
      await tester.pump();

      final confirm = tester.widget<AppButton>(confirmFinder);
      expect(confirm.isLoading, isTrue);
      expect(confirm.onPressed, isNull);

      await tapForuiControl(tester, confirmFinder);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
    });

    testWidgets('FUNC-H10: slots unavailable shows warning retry and disables confirm', (tester) async {
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

    testWidgets('FUNC-H11: confirm in progress shows loading indicator and disables button', (tester) async {
      final client = SlowCreateAppointmentRpcClient();

      await pumpCard(tester, client: client, slot: selectedSlot);

      final confirmFinder = find.byKey(const Key('simplified_slot_confirm'));
      await tapForuiControl(tester, confirmFinder);
      await tester.pump();

      final confirm = tester.widget<AppButton>(confirmFinder);
      expect(confirm.isLoading, isTrue);
      expect(confirm.onPressed, isNull);
      expect(find.byType(FCircularProgress), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    testWidgets('FUNC-H12: summary card uses mint teal gradient decoration', (tester) async {
      final client = AppointmentRpcTestClient();
      await pumpCard(tester, client: client, slot: selectedSlot);

      final card = find.byType(SimplifiedSlotSummaryCard);
      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(of: card, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = decoratedBox.decoration as BoxDecoration;

      expect(decoration.gradient, isA<LinearGradient>());
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors.length, greaterThanOrEqualTo(2));
    });

    testWidgets('bug-fix: notes too long blocks confirm with validation message', (tester) async {
      final client = AppointmentRpcTestClient();
      final longNotes = 'x' * 2001;

      await pumpCard(tester, client: client, slot: selectedSlot, notes: longNotes);

      expect(find.text('Notes must be 2000 characters or fewer.'), findsOneWidget);
      final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
      expect(confirm.onPressed, isNull);
    });
  });
}
