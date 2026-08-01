import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
=======
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
>>>>>>> master
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_status_actions.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_widget_test_harness.dart';

void main() {
  Future<void> pumpTimeline(
    WidgetTester tester, {
    required AppointmentDetail detail,
    Size surfaceSize = const Size(1280, 900),
  }) async {
    final repo = HarnessAppointmentRepository();
    final overrides = harnessDetailProviderOverrides(
      appointmentRepo: repo,
      detail: detail,
    );

    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: harnessMaterialApp(
          child: Scaffold(
            body: AppointmentStatusTimelineWidget(
              detail: detail,
<<<<<<< HEAD
              siblingAppointments: const [],
              shiftLookup: AppointmentQueueShiftDoctorLookup.empty,
              onChanged: () {},
=======
              doctorPresentation: null,
              statusActions: AppointmentDetailStatusActions(
                detail: detail,
                siblingAppointments: const [],
                shiftLookup: AppointmentQueueShiftDoctorLookup.empty,
                onChanged: () {},
              ),
>>>>>>> master
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  group('AppointmentStatusTimelineWidget', () {
    testWidgets('trivial: mid-flow appointment renders main flow step labels', (tester) async {
      final detail = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await pumpTimeline(tester, detail: detail);

      expect(find.text('Status journey'), findsOneWidget);
      for (final status in AppointmentStatusTimeline.mainFlow) {
        expect(find.text(status.label), findsWidgets);
      }
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.byType(AppointmentDetailStatusActions), findsOneWidget);
    });

    testWidgets('advanced: terminal cancelled shows overlay label and description', (tester) async {
      final detail = buildAppointmentDetail(status: AppointmentStatus.cancelled);
      await pumpTimeline(tester, detail: detail);

      expect(find.text('Cancelled'), findsWidgets);
      expect(
        find.text(AppointmentStatusTimeline.stepDescription(AppointmentStatus.cancelled)),
        findsOneWidget,
      );
      expect(find.text('Ended early'), findsOneWidget);
    });

    testWidgets('advanced: terminal completed shows overlay card', (tester) async {
      final detail = buildAppointmentDetail(status: AppointmentStatus.completed);
      await pumpTimeline(tester, detail: detail);

      expect(find.text('Completed'), findsWidgets);
      expect(
        find.text(AppointmentStatusTimeline.stepDescription(AppointmentStatus.completed)),
        findsOneWidget,
      );
    });

    testWidgets('edge case: builds horizontal layout at wide width', (tester) async {
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);
      await pumpTimeline(tester, detail: detail, surfaceSize: const Size(1280, 900));

      expect(find.text('Checked in'), findsWidgets);
      expect(find.text('Status journey'), findsOneWidget);
    });

    testWidgets('edge case: builds vertical layout at narrow width', (tester) async {
      final detail = buildAppointmentDetail(status: AppointmentStatus.checkedIn);
      await pumpTimeline(tester, detail: detail, surfaceSize: const Size(400, 900));

      expect(find.text('Checked in'), findsWidgets);
      expect(find.text('Status journey'), findsOneWidget);
    });
  });
}
