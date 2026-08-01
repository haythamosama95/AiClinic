import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/clinic-management/presentation/components/staff_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_tab.dart';

import 'clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('StaffTab empty state shows add staff action', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: StaffTab(
        staff: const [],
        branches: [clinicMgmtSampleBranch()],
        onAdd: (_) async {},
        onUpdate: (_, _) async {},
        onRemove: (_) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('No staff accounts yet'), findsOneWidget);
    expect(find.text('Add staff member'), findsWidgets);
  });

  testWidgets('StaffTab renders staff names in list', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: StaffTab(
        staff: [
          clinicMgmtSampleStaff(),
          clinicMgmtSampleStaff(
            id: '33333333-3333-4333-8333-333333333333',
            fullName: 'John Smith',
            username: 'john',
          ),
        ],
        branches: [clinicMgmtSampleBranch()],
        onAdd: (_) async {},
        onUpdate: (_, _) async {},
        onRemove: (_) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('John Smith'), findsOneWidget);
    expect(find.textContaining('@jane'), findsOneWidget);
  });

  testWidgets('StaffTab search filters list and shows no-results state', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: StaffTab(
        staff: [
          clinicMgmtSampleStaff(),
          clinicMgmtSampleStaff(
            id: '33333333-3333-4333-8333-333333333333',
            fullName: 'John Smith',
            username: 'john',
          ),
        ],
        branches: [clinicMgmtSampleBranch()],
        onAdd: (_) async {},
        onUpdate: (_, _) async {},
        onRemove: (_) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    final searchField = find.byType(EditableText).first;
    await tester.enterText(searchField, 'John');
    await settleClinicMgmtWidget(tester);

    expect(find.text('John Smith'), findsOneWidget);
    expect(find.text('Jane Doe'), findsNothing);
    expect(find.textContaining('Search: John'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'nobody-here');
    await settleClinicMgmtWidget(tester);
    await settleClinicMgmtWidget(tester);

    expect(find.text('No staff match'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('StaffTab row tap opens StaffDetailDialog', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: StaffTab(
        staff: [clinicMgmtSampleStaff()],
        branches: [clinicMgmtSampleBranch()],
        onAdd: (_) async {},
        onUpdate: (_, _) async {},
        onRemove: (_) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Jane Doe'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Profile details, role, and branch access.'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-name'), findsOneWidget);
  });

  testWidgets('StaffTab add staff opens StaffFormDialog', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: StaffTab(
        staff: [clinicMgmtSampleStaff()],
        branches: [clinicMgmtSampleBranch()],
        onAdd: (_) async {},
        onUpdate: (_, _) async {},
        onRemove: (_) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Add staff member').first);
    await settleClinicMgmtWidget(tester);

    expect(find.byType(StaffFormDialog), findsOneWidget);
    expect(find.text('Create a sign-in account with a role and branch assignments.'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-username'), findsOneWidget);
    expect(find.bySemanticsIdentifier('staff-password'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}
