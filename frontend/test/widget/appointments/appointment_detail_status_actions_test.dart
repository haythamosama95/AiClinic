import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_status_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/role_permission_seed.dart';
import 'detail_widget_test_harness.dart';

void main() {
  Future<void> pumpStatusActions(
    WidgetTester tester, {
    required HarnessAppointmentRepository repo,
    required AppointmentDetail detail,
    List<AppointmentListItem> siblings = const [],
    AppointmentQueueShiftDoctorLookup? shiftLookup,
    Set<String>? permissions,
    VoidCallback? onChanged,
  }) async {
    final overrides = harnessDetailProviderOverrides(
      appointmentRepo: repo,
      detail: detail,
      siblings: siblings,
      shiftLookup: shiftLookup,
      auth: harnessAuthSession(permissions: permissions ?? RolePermissionSeed.receptionist),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: harnessMaterialApp(
          child: Scaffold(
            body: AppointmentDetailStatusActions(
              detail: detail,
              siblingAppointments: siblings,
              shiftLookup: shiftLookup ?? AppointmentQueueShiftDoctorLookup.empty,
              onChanged: onChanged ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('AppointmentDetailStatusActions', () {
    testWidgets('trivial: scheduled shows Confirm advance without revert', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.scheduled);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      expect(find.byKey(const Key('appointment_control_revert_status')), findsNothing);
      expect(find.byKey(const Key('appointment_control_advance_status')), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.byKey(const Key('appointment_control_no_show')), findsOneWidget);
      expect(find.byKey(const Key('appointment_control_cancel')), findsOneWidget);
    });

    testWidgets('advanced: confirmed shows Undo confirm and Check in labels', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      expect(find.text('Undo confirm'), findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
    });

    testWidgets('advanced: tapping advance updates status and calls onChanged', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.scheduled);
      var changed = false;
      await pumpStatusActions(
        tester,
        repo: repo,
        detail: detail,
        onChanged: () => changed = true,
      );

      await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.statusUpdateCallCount, 1);
      expect(repo.lastStatusUpdate, AppointmentStatus.confirmed);
      expect(changed, isTrue);
    });

    testWidgets('advanced: revert dialog Keep current status dismisses without update', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_revert_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Keep current status'), findsOneWidget);
      await tester.tap(find.text('Keep current status'));
      await tester.pump();

      expect(repo.statusUpdateCallCount, 0);
    });

    testWidgets('advanced: revert dialog confirming performs status update', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_revert_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Undo confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.statusUpdateCallCount, 1);
      expect(repo.lastStatusUpdate, AppointmentStatus.scheduled);
    });

    testWidgets('advanced: no-show dialog dismiss and confirm paths', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_no_show')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Keep appointment'), findsOneWidget);
      await tester.tap(find.text('Keep appointment'));
      await tester.pump();
      expect(repo.noShowCallCount, 0);

      await tester.tap(find.byKey(const Key('appointment_control_no_show')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Mark no-show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.noShowCallCount, 1);
    });

    testWidgets('advanced: cancel opens cancel appointment dialog', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.scheduled);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cancel appointment?'), findsOneWidget);
      expect(find.text('Keep appointment'), findsOneWidget);
    });

    testWidgets('advanced: checked-in unassigned start opens doctor picker when required', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(
        status: AppointmentStatus.checkedIn,
        doctorId: null,
        doctorName: null,
      );
      final lookup = buildShiftLookup();
      await pumpStatusActions(
        tester,
        repo: repo,
        detail: detail,
        shiftLookup: lookup,
      );

      await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Who will see this patient?'), findsOneWidget);
    });

    testWidgets('advanced: checked-in with assigned doctor skips picker', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Who will see this patient?'), findsNothing);
      expect(repo.statusUpdateCallCount, 1);
      expect(repo.lastStatusUpdate, AppointmentStatus.inProgress);
    });

    testWidgets('invalid state: disabled advance shows toast with disabledReason', (tester) async {
      final repo = HarnessAppointmentRepository();
      final detail = buildAppointmentDetail(status: AppointmentStatus.inProgress);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tapDisabledActionForToast(
        tester,
        const Key('appointment_control_advance_status'),
      );

      expect(
        find.text('Complete this appointment from the visit workflow.'),
        findsOneWidget,
      );
    });

    testWidgets('invalid state: RpcFailure surfaces appointmentMessageForRpc', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.statusUpdateFailure = RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'FORBIDDEN',
          errorMessage: 'denied',
        ),
      );
      final detail = buildAppointmentDetail(status: AppointmentStatus.scheduled);
      await pumpStatusActions(tester, repo: repo, detail: detail);

      await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(appointmentMessageForRpc(repo.statusUpdateFailure!)),
        findsOneWidget,
      );
    });
  });
}
