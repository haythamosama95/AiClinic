import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/appointment_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

void main() {
  group('AppointmentCalendarPage display', () {
    group('CAL-I — display and visual consistency (widget)', () {
      testWidgets('CAL-I02: week view appointment tile shows doctor in notes', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);

        final calendar = calendarWidget(tester);
        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        final appointment = dataSource.appointments!.single as Appointment;

        expect(appointment.notes, 'Dr Test');
        expect(appointment.subject, 'Test Patient');
      });

      testWidgets('CAL-I04: timeline day uses full-height appointment tiles', (tester) async {
        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          rpcClient: DoctorAwareAppointmentRpcClient(),
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Timeline Day');
        await tester.pump(const Duration(milliseconds: 200));

        expect(calendarWidget(tester).timeSlotViewSettings.timelineAppointmentHeight, 120);
      });

      testWidgets('CAL-I05: calendar uses semantic theme colors in light and dark mode', (tester) async {
        for (final theme in [AppTheme.light(), AppTheme.dark()]) {
          await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), theme: theme);
          await waitForCalendarLoaded(tester);

          final calendar = calendarWidget(tester);
          expect(calendar.cellBorderColor, isNotNull);
          expect(find.byType(AppointmentCalendarHeaderBar), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });

      testWidgets('CAL-I06: calendar layout fits common desktop widths without overflow', (tester) async {
        for (final width in [1280.0, 1024.0, 800.0]) {
          await pumpAppointmentCalendarPage(tester, authState: calendarAuthState(), surfaceSize: Size(width, 900));
          await waitForCalendarLoaded(tester);

          expect(find.byType(SfCalendar), findsOneWidget);
          expect(find.byType(AppointmentCalendarHeaderBar), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      });

      testWidgets('CAL-I08: unassigned appointment maps to Unassigned resource row', (tester) async {
        final start = appointmentTestStartTime();
        final client = calendarClientWithItems([
          {...appointmentRpcDefaultListItem(startLocal: start), 'doctor_id': null, 'doctor_name': null},
        ]);

        await pumpAppointmentCalendarPage(
          tester,
          authState: calendarAuthState(),
          rpcClient: client,
          staffRepository: CalendarDoctorsStubStaffRepository(),
        );
        await waitForCalendarLoaded(tester);

        await tapCalendarViewTab(tester, 'Timeline Day');
        await tester.pump(const Duration(milliseconds: 200));

        final calendar = calendarWidget(tester);
        final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
        final appointment = dataSource.appointments!.single as Appointment;

        expect(appointment.resourceIds, [appointmentCalendarUnassignedResourceId]);
        expect(dataSource.resources!.any((resource) => resource.displayName == 'Unassigned'), isTrue);
      });
    });
  });
}
