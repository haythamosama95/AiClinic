import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_hero.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/organization_tab.dart';

import 'clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('OrganizationTab renders organization name and hero stats', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: OrganizationTab(
        organization: clinicMgmtSampleOrganization,
        branchCount: 3,
        staffCount: 12,
        activeBranchCount: 2,
        onSave: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.byType(ClinicHero), findsOneWidget);
    expect(find.text('Test Clinic'), findsWidgets);
    expect(find.text('Branches'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Team members'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Active locations'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('OrganizationTab edit enables fields and cancel resets draft', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: OrganizationTab(
        organization: clinicMgmtSampleOrganization,
        branchCount: 1,
        staffCount: 1,
        activeBranchCount: 1,
        onSave: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Edit organization'));
    await settleClinicMgmtWidget(tester);

    await tester.enterText(clinicMgmtEditableText('org-name'), 'Changed Clinic');
    await settleClinicMgmtWidget(tester);

    expect(find.text('Changed Clinic'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Test Clinic'), findsWidgets);
    expect(find.text('Changed Clinic'), findsNothing);
    expect(find.text('Edit organization'), findsOneWidget);
  });

  testWidgets('OrganizationTab save with invalid name shows validation', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      child: OrganizationTab(
        organization: clinicMgmtSampleOrganization,
        branchCount: 1,
        staffCount: 1,
        activeBranchCount: 1,
        onSave: (_) {},
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Edit organization'));
    await settleClinicMgmtWidget(tester);

    await tester.enterText(clinicMgmtEditableText('org-name'), '   ');
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Save changes'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Organization name is required'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('OrganizationTab save with valid data calls onSave', (tester) async {
    OrganizationProfile? saved;

    await pumpClinicMgmtWidget(
      tester,
      child: OrganizationTab(
        organization: clinicMgmtSampleOrganization,
        branchCount: 1,
        staffCount: 1,
        activeBranchCount: 1,
        onSave: (profile) => saved = profile,
      ),
    );
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Edit organization'));
    await settleClinicMgmtWidget(tester);

    await tester.enterText(clinicMgmtEditableText('org-name'), 'Renamed Clinic');
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Save changes'));
    await settleClinicMgmtWidget(tester);

    expect(saved, isNotNull);
    expect(saved!.name, 'Renamed Clinic');
    expect(saved!.currencyCode, 'USD');
    expect(saved!.timezone, 'America/New_York');
    expect(find.text('Edit organization'), findsOneWidget);
  });
}
