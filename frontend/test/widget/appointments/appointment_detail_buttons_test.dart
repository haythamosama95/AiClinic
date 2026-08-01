<<<<<<< HEAD
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
=======
import 'package:ai_clinic/core/rpc/rpc_result.dart';
>>>>>>> master
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_edit_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_invoice_summary_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_open_visit_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/role_permission_seed.dart';
import 'detail_widget_test_harness.dart';

void main() {
  Future<void> pumpDetailButton(
    WidgetTester tester, {
    required Widget button,
    required HarnessAppointmentRepository appointmentRepo,
    HarnessVisitRepository? visitRepo,
    HarnessInvoiceRepository? invoiceRepo,
    Set<String>? permissions,
    bool withVisitRoute = false,
  }) async {
    final overrides = harnessDetailProviderOverrides(
      appointmentRepo: appointmentRepo,
      visitRepo: visitRepo,
      invoiceRepo: invoiceRepo,
      auth: harnessAuthSession(permissions: permissions ?? RolePermissionSeed.administrator),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final home = Scaffold(body: Center(child: button));

    if (withVisitRoute) {
      final router = GoRouter(
        initialLocation: '/test',
        routes: [
<<<<<<< HEAD
          GoRoute(path: '/test', builder: (_, __) => home),
=======
          GoRoute(path: '/test', builder: (_, _) => home),
>>>>>>> master
          GoRoute(
            path: '/visits/:visitId/document',
            builder: (context, state) => Scaffold(
              body: Text(
                'Visit ${state.pathParameters['visitId']}',
                key: Key('visit_stub_${state.pathParameters['visitId']}'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: harnessMaterialApp(router: router),
        ),
      );
    } else {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: harnessMaterialApp(child: home),
        ),
      );
    }
    await tester.pump();
  }

  group('AppointmentDetailOpenVisitButton', () {
    testWidgets('trivial: hidden without visit documentation permission', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);
      await pumpDetailButton(
        tester,
        appointmentRepo: repo,
        button: AppointmentDetailOpenVisitButton(detail: detail),
        permissions: RolePermissionSeed.receptionist,
      );

      expect(find.byKey(const Key('appointment_detail_open_visit')), findsNothing);
    });

    testWidgets('advanced: shown when permitted and navigates to visit document', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final visitRepo = HarnessVisitRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        visitRepo: visitRepo,
        button: AppointmentDetailOpenVisitButton(detail: detail),
        permissions: RolePermissionSeed.doctor,
        withVisitRoute: true,
      );

      expect(find.byKey(const Key('appointment_detail_open_visit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('appointment_detail_open_visit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(Key('visit_stub_$detailTestVisitId')), findsOneWidget);
    });

    testWidgets('invalid state: repository error shows visit rpc message toast', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final visitRepo = HarnessVisitRepository();
      visitRepo.visitByAppointmentFailure = RpcFailure(
        RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'denied'),
      );
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        visitRepo: visitRepo,
        button: AppointmentDetailOpenVisitButton(detail: detail),
        permissions: RolePermissionSeed.doctor,
      );

      await tester.tap(find.byKey(const Key('appointment_detail_open_visit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(visitMessageForRpc(visitRepo.visitByAppointmentFailure!)),
        findsOneWidget,
      );
    });
  });

  group('AppointmentDetailEditButton', () {
    testWidgets('advanced: tapping opens booking sheet in edit mode', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.scheduled);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        button: AppointmentDetailEditButton(detail: detail),
        permissions: RolePermissionSeed.receptionist,
      );

      await tester.tap(find.byKey(const Key('appointment_detail_edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit appointment'), findsWidgets);
      expect(find.byType(AppointmentBookingSheet), findsOneWidget);
      expect(find.text('Test Patient'), findsWidgets);
    });
  });

  group('AppointmentDetailInvoiceSummaryButton', () {
    testWidgets('trivial: hidden when not completed', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        button: AppointmentDetailInvoiceSummaryButton(detail: detail),
        permissions: RolePermissionSeed.receptionist,
      );

      expect(find.byKey(const Key('appointment_detail_invoice_summary')), findsNothing);
    });

    testWidgets('trivial: hidden without invoice list permission', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.completed);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        button: AppointmentDetailInvoiceSummaryButton(detail: detail),
        permissions: RolePermissionSeed.doctor,
      );

      expect(find.byKey(const Key('appointment_detail_invoice_summary')), findsNothing);
    });

    testWidgets('advanced: shown when completed and permitted; opens invoice summary', (tester) async {
      final appointmentRepo = HarnessAppointmentRepository();
      final visitRepo = HarnessVisitRepository();
      final invoiceRepo = HarnessInvoiceRepository();
      invoiceRepo.listItem = buildHarnessInvoiceListItem();
      final detail = buildAppointmentDetail(status: AppointmentStatus.completed);

      await pumpDetailButton(
        tester,
        appointmentRepo: appointmentRepo,
        visitRepo: visitRepo,
        invoiceRepo: invoiceRepo,
        button: AppointmentDetailInvoiceSummaryButton(detail: detail),
        permissions: RolePermissionSeed.receptionist,
      );

      expect(find.byKey(const Key('appointment_detail_invoice_summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('appointment_detail_invoice_summary')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Invoice summary'), findsWidgets);
    });
  });
}
