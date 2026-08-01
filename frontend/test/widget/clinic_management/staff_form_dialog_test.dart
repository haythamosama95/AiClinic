import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/clinic-management/presentation/components/staff_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';

import 'clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('StaffFormDialog create mode requires username and password fields', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: StaffFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: StaffFormMode.create,
        branches: [clinicMgmtSampleBranch()],
        initialValues: emptyStaffFormValues(),
        onSubmit: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Add staff member'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-username'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-password'), findsOneWidget);
  });

  testWidgets('StaffFormDialog edit mode shows existing values and hides credentials', (tester) async {
    final staff = clinicMgmtSampleStaff();

    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: StaffFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: StaffFormMode.edit,
        branches: [clinicMgmtSampleBranch()],
        initialValues: staffToFormValues(staff),
        onSubmit: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Edit staff member'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('jane'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-username'), findsNothing);
    expect(find.bySemanticsIdentifier('staff-password'), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('StaffFormDialog shows validation on required fields', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      scrollable: false,
      child: StaffFormDialog(
        open: true,
        onOpenChange: (_) {},
        mode: StaffFormMode.create,
        branches: [clinicMgmtSampleBranch()],
        initialValues: emptyStaffFormValues(),
        onSubmit: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Create account'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Full name is required'), findsOneWidget);
    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Select a role'), findsWidgets);
    expect(find.text('Select at least one branch assignment'), findsOneWidget);
  });
}
