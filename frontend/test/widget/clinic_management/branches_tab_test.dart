import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/clinic-management/presentation/components/branch_form_dialog.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/branches_tab.dart';

import 'clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('BranchesTab empty state shows Add branch button', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: BranchesTab(
        branches: const [],
        onAddBranch: (_) async {},
        onUpdateBranch: (_, _) async {},
        onRemoveBranch: (_) async {},
        onToggleBranchActive: ({required branchId, required isActive}) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('No branches yet'), findsOneWidget);
    expect(find.text('Add branch'), findsWidgets);
  });

  testWidgets('BranchesTab renders branch cards with name and code', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: BranchesTab(
        branches: [
          clinicMgmtSampleBranch(),
          clinicMgmtSampleBranch(
            id: '55555555-5555-4555-8555-555555555555',
            name: 'Uptown',
            code: 'UP',
          ),
        ],
        onAddBranch: (_) async {},
        onUpdateBranch: (_, _) async {},
        onRemoveBranch: (_) async {},
        onToggleBranchActive: ({required branchId, required isActive}) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Main Branch'), findsOneWidget);
    expect(find.text('MAIN'), findsOneWidget);
    expect(find.text('Uptown'), findsOneWidget);
    expect(find.text('UP'), findsOneWidget);
  });

  testWidgets('BranchesTab search filters list and shows no-results state', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: BranchesTab(
        branches: [
          clinicMgmtSampleBranch(),
          clinicMgmtSampleBranch(
            id: '55555555-5555-4555-8555-555555555555',
            name: 'Uptown',
            code: 'UP',
          ),
        ],
        onAddBranch: (_) async {},
        onUpdateBranch: (_, _) async {},
        onRemoveBranch: (_) async {},
        onToggleBranchActive: ({required branchId, required isActive}) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    final searchField = find.byType(EditableText).first;
    await tester.enterText(searchField, 'Uptown');
    await settleClinicMgmtWidget(tester);

    expect(find.text('Uptown'), findsWidgets);
    expect(find.text('Main Branch'), findsNothing);

    await tester.enterText(find.byType(EditableText).first, 'missing-branch');
    await settleClinicMgmtWidget(tester);

    expect(find.text('No branches match'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('BranchesTab add branch opens dialog and validates required name', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: BranchesTab(
        branches: [clinicMgmtSampleBranch()],
        onAddBranch: (_) async {},
        onUpdateBranch: (_, _) async {},
        onRemoveBranch: (_) async {},
        onToggleBranchActive: ({required branchId, required isActive}) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Add branch').first);
    await settleClinicMgmtWidget(tester);

    expect(find.byType(BranchFormDialog), findsOneWidget);
    expect(find.text('Add branch'), findsWidgets);
    expect(find.text('Create branch'), findsOneWidget);

    await tester.tap(find.text('Create branch'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Branch name is required'), findsOneWidget);
  });

  testWidgets('BranchesTab delete shows confirmation dialog', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: BranchesTab(
        branches: [clinicMgmtSampleBranch()],
        onAddBranch: (_) async {},
        onUpdateBranch: (_, _) async {},
        onRemoveBranch: (_) async {},
        onToggleBranchActive: ({required branchId, required isActive}) async {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.bySemanticsLabel('Branch actions').first);
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Delete'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Delete branch?'), findsOneWidget);
    expect(find.text('Delete branch'), findsOneWidget);
    expect(find.textContaining('Main Branch'), findsWidgets);
  });
}
