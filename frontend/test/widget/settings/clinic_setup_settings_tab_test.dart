import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/clinic_setup_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

void main() {
  group('ClinicSetupSettingsTab', () {
    const profile = OrganizationProfile(
      id: 'org-1',
      name: 'Demo Clinic',
      logoUrl: 'https://example.com/logo.png',
      currencyCode: 'EGP',
      timezone: 'Africa/Cairo',
    );

    const branches = [
      BranchListItem(
        id: 'branch-1',
        name: 'Main Branch',
        isActive: true,
        code: 'MAIN',
        address: '123 Street',
        phone: '1234567890',
        mapsUrl: 'https://maps.example.com',
      ),
    ];

    Future<void> pumpTab(
      WidgetTester tester, {
      OrganizationProfile? organization,
      List<BranchListItem> branchList = branches,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clinicSetupOrganizationProvider.overrideWith((ref) async => organization),
            clinicSetupBranchesProvider.overrideWith((ref) async => branchList),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: ClinicSetupSettingsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows organization and branch cards in read-only mode', (tester) async {
      await pumpTab(tester, organization: profile);

      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsOneWidget);
      expect(find.text('Main Branch (MAIN)'), findsOneWidget);
      expect(find.text('123 Street'), findsOneWidget);
      expect(find.text('Organization name *'), findsNothing);
      expect(find.text('Branch name *'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Add branch'), findsOneWidget);
      expect(find.byIcon(Icons.add_business_outlined), findsOneWidget);
      expect(find.byTooltip('Edit'), findsNWidgets(2));
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byTooltip('Deactivate branch'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('add branch button opens blurred create branch modal', (tester) async {
      await pumpTab(tester, organization: profile);

      await tester.tap(find.widgetWithText(AppButton, 'Add branch'));
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Branch name *'), findsOneWidget);
      expect(find.text('Branch code *'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Create branch'), findsOneWidget);
    });

    testWidgets('inactive branch shows activate and permanent delete buttons', (tester) async {
      const inactiveBranches = [BranchListItem(id: 'branch-1', name: 'Closed Branch', isActive: false, code: 'CLOSED')];

      await pumpTab(tester, organization: profile, branchList: inactiveBranches);

      expect(find.text('Closed Branch (CLOSED)'), findsOneWidget);
      expect(find.text('This branch is inactive.'), findsNothing);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.byTooltip('Inactive branch'), findsOneWidget);
      expect(find.byTooltip('Activate branch'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byTooltip('Delete branch permanently'), findsOneWidget);
      expect(find.byIcon(Icons.delete_forever_outlined), findsOneWidget);
      expect(find.byTooltip('Deactivate branch'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('permanent delete button opens confirmation dialog', (tester) async {
      const inactiveBranches = [BranchListItem(id: 'branch-1', name: 'Closed Branch', isActive: false, code: 'CLOSED')];

      await pumpTab(tester, organization: profile, branchList: inactiveBranches);

      await tester.tap(find.byTooltip('Delete branch permanently'));
      await tester.pumpAndSettle();

      expect(find.text('Delete branch permanently?'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Delete branch'), findsOneWidget);
    });

    testWidgets('deactivate button opens confirmation dialog', (tester) async {
      await pumpTab(tester, organization: profile);

      await tester.tap(find.byTooltip('Deactivate branch'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate branch?'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Deactivate branch'), findsOneWidget);
    });

    testWidgets('edit button reveals organization form fields', (tester) async {
      await pumpTab(tester, organization: profile);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();

      expect(find.text('Organization name *'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('organization card uses settings section layout', (tester) async {
      await pumpTab(tester, organization: profile);

      expect(find.byType(SettingsSectionCard), findsOneWidget);
    });
  });
}
