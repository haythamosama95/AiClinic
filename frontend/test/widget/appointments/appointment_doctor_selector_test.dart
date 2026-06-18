import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_calendar_test_support.dart';

void main() {
  group('AppointmentDoctorSelector', () {
    testWidgets('highlights doctors not assigned to the booking branch', (tester) async {
      const assignedDoctor = StaffListItem(
        id: calendarTestDoctorAId,
        fullName: 'Dr. Ada',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
      );
      const unassignedDoctor = StaffListItem(
        id: calendarTestDoctorBId,
        fullName: 'Dr. Ben',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: calendarTestBranchBId, name: 'Branch B', isPrimary: true)],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Scaffold(
            body: AppointmentDoctorSelector(
              branchId: calendarTestBranchAId,
              doctors: const [assignedDoctor, unassignedDoctor],
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
      await tester.pumpAndSettle();

      expect(find.text('Not available at this branch'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      final doctorNames = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((label) => label == 'Dr. Ada' || label == 'Dr. Ben')
          .toList();
      expect(doctorNames, ['Dr. Ada', 'Dr. Ben']);
    });

    testWidgets('close button dismisses the doctor dropdown', (tester) async {
      const doctor = StaffListItem(
        id: calendarTestDoctorAId,
        fullName: 'Dr. Ada',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Scaffold(
            body: AppointmentDoctorSelector(
              branchId: calendarTestBranchAId,
              doctors: const [doctor],
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Ada'), findsWidgets);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Not available at this branch'), findsNothing);
    });
  });
}
