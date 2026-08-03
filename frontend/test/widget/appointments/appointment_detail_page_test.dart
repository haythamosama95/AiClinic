import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_detail_page.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_widget_test_harness.dart';
import '../../helpers/breadcrumb_test_support.dart';

void main() {
  group('AppointmentDetailPage', () {
    testWidgets('invalid state: permission denied hides detail content', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        auth: harnessAuthSession(permissions: {'patients.view'}),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('You do not have permission to view appointments.'), findsOneWidget);
      expect(find.text('Test Patient'), findsNothing);
      expect(find.text('Status journey'), findsNothing);
    });

    testWidgets('trivial: loading shows Loading title without preview', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        loadingDetail: true,
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('Loading…'), findsWidgets);
      expect(find.byType(AppProgress), findsWidgets);
    });

    testWidgets('advanced: loading with preview shows patient name', (tester) async {
      final repo = HarnessAppointmentRepository();
      final preview = buildAppointmentListItem(patientName: 'Preview Patient');
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        loadingDetail: true,
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        extra: AppointmentDetailRouteExtra(preview: preview),
      );
      await tester.pump();

      expect(find.text('Preview Patient'), findsWidgets);
      expect(find.text('Scheduled'), findsWidgets);
    });

    testWidgets('invalid state: NOT_FOUND Back falls back to calendar when cannot pop', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detailError: RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'NOT_FOUND',
            errorMessage: 'appointment not found',
          ),
        ),
      );

      final router = buildDetailBackNavigationRouter(
        appointmentId: detailTestAppointmentId,
        detailPage: AppointmentDetailPage(appointmentId: detailTestAppointmentId),
        initialLocation: AppRoutes.appointmentDetail(detailTestAppointmentId),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        router: router,
      );
      await tester.pump();

      expect(router.state.uri.toString(), AppRoutes.appointmentDetail(detailTestAppointmentId));
      expect(find.text('Appointment not found'), findsWidgets);
      expect(find.text('Back to calendar'), findsOneWidget);

      await tester.tap(find.text('Back to calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(router.state.uri.toString(), AppRoutes.appointmentsCalendar);
      expect(find.byKey(const Key('calendar_stub')), findsOneWidget);
    });

    testWidgets('advanced: Back to calendar pops when navigator can pop', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detailError: RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'NOT_FOUND',
            errorMessage: 'appointment not found',
          ),
        ),
      );

      final router = buildDetailBackNavigationRouter(
        appointmentId: detailTestAppointmentId,
        detailPage: AppointmentDetailPage(appointmentId: detailTestAppointmentId),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        router: router,
      );
      await tester.pump();

      expect(router.state.uri.toString(), AppRoutes.appointmentsCalendar);
      expect(find.byKey(const Key('calendar_stub')), findsOneWidget);

      router.push(AppRoutes.appointmentDetail(detailTestAppointmentId));
      await tester.pump();
      await tester.pump();

      expect(router.state.uri.toString(), AppRoutes.appointmentDetail(detailTestAppointmentId));
      expect(find.text('Back to calendar'), findsOneWidget);

      await tester.tap(find.text('Back to calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(router.state.uri.toString(), AppRoutes.appointmentsCalendar);
      expect(find.byKey(const Key('calendar_stub')), findsOneWidget);
    });

    testWidgets('invalid state: other error shows message and Retry refetches', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.failGetAppointmentTimes = 1;
      final overrides = harnessDetailProviderOverrides(appointmentRepo: repo);
      repo.detailOverride = buildAppointmentDetail(patientName: 'Reloaded Patient');

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Unable to load appointment'), findsOneWidget);
      expect(find.textContaining('Network blew up'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.getAppointmentCallCount, 2);
      expect(find.text('Reloaded Patient'), findsWidgets);
    });

    testWidgets('trivial: data view shows patient, status chip, and fact chips', (tester) async {
      final detail = buildAppointmentDetail(
        patientName: 'Ahmed Hassan',
        status: AppointmentStatus.confirmed,
        notes: 'Bring labs',
      );
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: detail,
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Ahmed Hassan'), findsWidgets);
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Status journey'), findsOneWidget);
      expect(find.text('with Dr. Ada'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Bring labs'), findsOneWidget);
    });

    testWidgets('trivial: notes card absent when notes empty', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(notes: null, cancelReason: null),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('Notes'), findsNothing);
      expect(find.text('Cancellation reason'), findsNothing);
    });

    testWidgets('advanced: cancellation reason card when cancelReason set', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(
          status: AppointmentStatus.cancelled,
          cancelReason: 'Patient rescheduled',
        ),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('Cancellation reason'), findsOneWidget);
      expect(find.text('Patient rescheduled'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);
    });

    testWidgets('advanced: Record info audit chip opens panel after tap', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
      );
      await tester.pump();

      expect(find.text('Record info'), findsOneWidget);
      await tester.tap(find.text('Record info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Booked by'), findsOneWidget);
      expect(find.text('Last updated'), findsOneWidget);
    });

    testWidgets('advanced: Calendar breadcrumb navigates to calendar route', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(),
        breadcrumbTrail: calendarToAppointmentTrail(
          appointmentId: detailTestAppointmentId,
          appointmentLabel: 'Test Patient',
        ),
      );

      final router = buildDetailTestRouter(
        appointmentId: detailTestAppointmentId,
        detailPage: AppointmentDetailPage(appointmentId: detailTestAppointmentId),
        initialLocation: AppRoutes.appointmentDetail(detailTestAppointmentId),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        router: router,
      );
      await tester.pump();

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stub')), findsOneWidget);
    });

    testWidgets('advanced: queue origin shows Queue parent instead of Calendar', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(patientName: 'Queue Patient'),
        breadcrumbTrail: queueToAppointmentTrail(
          appointmentId: detailTestAppointmentId,
          appointmentLabel: 'Queue Patient',
        ),
      );

      final router = buildDetailTestRouter(
        appointmentId: detailTestAppointmentId,
        detailPage: AppointmentDetailPage(appointmentId: detailTestAppointmentId),
        initialLocation: AppRoutes.appointmentDetail(detailTestAppointmentId),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        router: router,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Calendar'), findsNothing);
      expect(find.text('Queue Patient'), findsWidgets);
    });

    testWidgets('advanced: Patient profile pushes patient detail route', (tester) async {
      final repo = HarnessAppointmentRepository();
      final overrides = harnessDetailProviderOverrides(
        appointmentRepo: repo,
        detail: buildAppointmentDetail(patientId: detailTestPatientId),
      );

      final router = buildDetailTestRouter(
        appointmentId: detailTestAppointmentId,
        detailPage: AppointmentDetailPage(appointmentId: detailTestAppointmentId),
        initialLocation: AppRoutes.appointmentDetail(detailTestAppointmentId),
      );

      await pumpAppointmentDetail(
        tester,
        appointmentId: detailTestAppointmentId,
        overrides: overrides,
        router: router,
      );
      await tester.pump();

      await tester.tap(find.text('Patient profile'));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('patient_stub_$detailTestPatientId')), findsOneWidget);
    });
  });
}
