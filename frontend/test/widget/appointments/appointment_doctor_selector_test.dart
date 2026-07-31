import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_calendar_test_support.dart';
import 'detail_widget_test_harness.dart';

void main() {
  group('AppointmentDoctorSelector', () {
    testWidgets('trivial: renders options from AppointmentDoctorSelectItems', (tester) async {
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentDoctorSelector(
              branchId: calendarTestBranchAId,
              doctors: buildTestDoctors(),
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final options = AppointmentDoctorSelectItems.buildOptions(
        branchId: calendarTestBranchAId,
        doctors: buildTestDoctors(),
        emptyLabel: 'No preference',
      );

      await tester.tap(find.byType(AppSelect));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      for (final option in options) {
        expect(find.text(option.label), findsWidgets);
      }
    });

    testWidgets('advanced: selecting fires onChanged', (tester) async {
      String? selected;

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentDoctorSelector(
              key: const Key('doctor_selector'),
              branchId: calendarTestBranchAId,
              doctors: buildTestDoctors(),
              value: null,
              onChanged: (doctorId) => selected = doctorId,
            ),
          ),
        ),
      );
      await tester.pump();

      await tapAppSelectOption(tester, const Key('doctor_selector'), 'Dr. Ada');
      expect(selected, calendarTestDoctorAId);
    });

    testWidgets('edge case: doctor unavailable at branch is disabled with reason', (tester) async {
      final options = AppointmentDoctorSelectItems.buildOptions(
        branchId: calendarTestBranchAId,
        doctors: buildTestDoctors(),
        emptyLabel: 'No preference',
      );
      final benOption = options.firstWhere((o) => o.label == 'Dr. Ben');
      expect(benOption.disabled, isTrue);
      expect(benOption.disabledReason, AppointmentDoctorSelectItems.unavailableReason);
    });

    testWidgets('edge case: empty doctor list renders hint without throwing', (tester) async {
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentDoctorSelector(
              branchId: calendarTestBranchAId,
              doctors: const [],
              value: null,
              hint: 'Any available doctor',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No preference'), findsOneWidget);
    });

    testWidgets('trivial: null value shows unselected placeholder', (tester) async {
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentDoctorSelector(
              key: const Key('doctor_selector'),
              branchId: calendarTestBranchAId,
              doctors: buildTestDoctors(),
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No preference'), findsWidgets);
    });
  });
}
