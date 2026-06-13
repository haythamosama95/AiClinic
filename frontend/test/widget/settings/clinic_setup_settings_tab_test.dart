import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/clinic_setup_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';

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
      SettingsRpcTestClient? orgRpcClient,
      SettingsRpcTestClient? branchRpcClient,
      Future<OrganizationProfile?> Function()? organizationLoader,
      Future<List<BranchListItem>> Function()? branchesLoader,
      bool settle = true,
      StaffRole role = StaffRole.administrator,
      Set<String> permissions = const {'settings.manage_branches'},
    }) async {
      final orgClient = orgRpcClient ?? SettingsRpcTestClient();
      final branchClient = branchRpcClient ?? SettingsRpcTestClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _ClinicSetupAuthNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: role, permissions: permissions),
                ),
              ),
            ),
            organizationRepositoryProvider.overrideWithValue(OrganizationRepositoryImpl(orgClient)),
            branchRepositoryProvider.overrideWithValue(BranchRepositoryImpl(branchClient)),
            clinicSetupOrganizationProvider.overrideWith(
              (ref) async => organizationLoader != null ? await organizationLoader() : organization,
            ),
            clinicSetupBranchesProvider.overrideWith(
              (ref) async => branchesLoader != null ? await branchesLoader() : branchList,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: ClinicSetupSettingsTab()),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
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

    testWidgets('cancel edit restores original values', (tester) async {
      await pumpTab(tester, organization: profile);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'Changed Name');
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Demo Clinic'), findsOneWidget);
      expect(find.text('Changed Name'), findsNothing);
      expect(find.text('Organization name *'), findsNothing);
    });

    testWidgets('save organization calls update RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpTab(tester, organization: profile, orgRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'Updated Clinic');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'update_organization');
      expect(rpcClient.lastParams, containsPair('p_name', 'Updated Clinic'));
      expect(find.text('Organization name *'), findsNothing);
    });

    testWidgets('loading state shows spinner', (tester) async {
      final completer = Completer<OrganizationProfile?>();

      await pumpTab(tester, organizationLoader: () => completer.future, settle: false);

      expect(find.byType(AppCircularProgress), findsWidgets);
      completer.complete(profile);
      await tester.pumpAndSettle();
      expect(find.text('Demo Clinic'), findsOneWidget);
    });

    testWidgets('error state shows retry message', (tester) async {
      await pumpTab(tester, organizationLoader: () async => throw Exception('network'));

      expect(find.textContaining('Unable to load organization settings'), findsOneWidget);
    });

    testWidgets('confirm deactivate calls set_branch_active false', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpTab(tester, organization: profile, branchRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Deactivate branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Deactivate branch'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'set_branch_active');
      expect(rpcClient.lastParams, containsPair('p_is_active', false));
    });

    testWidgets('edit branch saves trimmed fields', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpTab(tester, organization: profile, branchRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Edit').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Branch name *'), '  Updated Branch  ');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'update_branch');
      expect(rpcClient.lastParams, containsPair('p_name', 'Updated Branch'));
    });

    testWidgets('working hours sheet opens from branch card edit mode', (tester) async {
      await pumpTab(tester, organization: profile);

      await tester.tap(find.byTooltip('Edit').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Working hours'));
      await tester.pumpAndSettle();

      expect(find.text('Monday'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
    });

    testWidgets('zero branches shows empty state guidance', (tester) async {
      await pumpTab(tester, organization: profile, branchList: const []);

      expect(find.text('No branches were found for your clinic.'), findsOneWidget);
    });

    testWidgets('unicode staff and branch names display correctly', (tester) async {
      const arabicProfile = OrganizationProfile(
        id: 'org-ar',
        name: 'مستشفى النور',
        currencyCode: 'EGP',
        timezone: 'Africa/Cairo',
      );
      const arabicBranches = [
        BranchListItem(id: 'branch-ar', name: 'عيادة المدينة', isActive: true, code: 'ARAB', address: 'شارع النيل'),
      ];

      await pumpTab(tester, organization: arabicProfile, branchList: arabicBranches);

      expect(find.text('مستشفى النور'), findsOneWidget);
      expect(find.textContaining('عيادة المدينة'), findsWidgets);
      expect(find.text('شارع النيل'), findsOneWidget);
    });

    testWidgets('unicode organization name saves via RPC', (tester) async {
      const arabicProfile = OrganizationProfile(
        id: 'org-ar',
        name: 'مستشفى النور',
        currencyCode: 'EGP',
        timezone: 'Africa/Cairo',
      );
      final rpcClient = SettingsRpcTestClient();
      await pumpTab(tester, organization: arabicProfile, orgRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'عيادة الشفاء');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'update_organization');
      expect(rpcClient.lastParams, containsPair('p_name', 'عيادة الشفاء'));
    });

    testWidgets('concurrent org edit shows error without silent overwrite', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'update_organization': {
            'success': false,
            'error_code': 'RPC_NOT_APPLIED',
            'error_message': 'Organization was updated by another administrator.',
          },
        },
      );
      await pumpTab(tester, organization: profile, orgRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'Stale Save Attempt');
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('another administrator'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Organization name *'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);
    });

    testWidgets('network loss during branch delete shows retry message', (tester) async {
      const inactiveBranches = [BranchListItem(id: 'branch-1', name: 'Closed Branch', isActive: false, code: 'CLOSED')];
      final rpcClient = SettingsRpcTestClient(
        rpcException: const PostgrestException(message: 'Connection timed out', code: 'timeout'),
      );

      await pumpTab(tester, organization: profile, branchList: inactiveBranches, branchRpcClient: rpcClient);

      await tester.tap(find.byTooltip('Delete branch permanently'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Delete branch'));
      await tester.pumpAndSettle();

      expect(find.textContaining('connectivity'), findsOneWidget);
      expect(find.text('Delete branch permanently?'), findsNothing);
    });

    testWidgets('user without clinic setup permission sees denial message', (tester) async {
      await pumpTab(tester, organization: profile, role: StaffRole.doctor, permissions: {'patients.view'});

      expect(find.textContaining('do not have permission'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });
  });
}

class _ClinicSetupAuthNotifier extends TestAuthSessionNotifier {
  _ClinicSetupAuthNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
