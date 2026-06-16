import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('CAL-A04 — booking permissions', () {
    testWidgets('create permission: valid submit creates appointment and shows success toast', (tester) async {
      final client = AppointmentRpcTestClient();
      final patient = samplePatientListItem(fullName: 'Booking Patient');
      final slotStart = appointmentTestStartTime(daysAhead: 7);
      final slotEnd = slotStart.add(const Duration(minutes: 30));
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('ListTile background color')) {
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => PresetAuthSessionNotifier(
                calendarAuthState(permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsRead}),
              ),
            ),
            appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
            patientRepositoryProvider.overrideWithValue(FakePatientRepository(patients: [patient])),
            searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(ref.watch(patientRepositoryProvider))),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: Scaffold(
              body: AppointmentBookingSheet(
                branchId: calendarTestBranchAId,
                schedule: BranchWorkingSchedule.defaultSchedule(),
                slotStart: slotStart,
                slotEnd: slotEnd,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Book');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Booking Patient'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('appointment_booking_submit')));
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(client.createAppointmentCalls, hasLength(1));
      expect(client.createAppointmentCalls.single['p_patient_id'], patient.id);
      expect(find.text('Appointment booked successfully.'), findsOneWidget);
    });
  });
}
