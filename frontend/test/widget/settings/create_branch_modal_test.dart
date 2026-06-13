import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/create_branch_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../support/settings_rpc_test_client.dart';

void main() {
  group('CreateBranchModal', () {
    Future<void> pumpWithModal(
      WidgetTester tester, {
      SettingsRpcTestClient? rpcClient,
      List<BranchListItem> branches = const [
        BranchListItem(id: 'branch-1', name: 'Main Branch', isActive: true, code: 'MAIN'),
      ],
    }) async {
      final client = rpcClient ?? SettingsRpcTestClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchRepositoryProvider.overrideWithValue(BranchRepositoryImpl(client)),
            clinicSetupBranchesProvider.overrideWith((ref) async => branches),
            clinicSetupOrganizationProvider.overrideWith(
              (ref) async => const OrganizationProfile(id: 'org-1', name: 'Demo Clinic'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: AppButton(label: 'Open', onPressed: () => CreateBranchModal.show(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> fillValidBranchForm(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(AppTextField, 'Branch name *'), 'East Wing');
      await tester.enterText(find.widgetWithText(AppTextField, 'Branch code *'), 'EAST');
      await tester.enterText(find.widgetWithText(AppTextField, 'Address *'), '2 East St');
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone *'), '5551234567');
      await tester.enterText(find.widgetWithText(AppTextField, 'Maps URL *'), 'https://maps.example.com/east');
      await tester.tap(find.text('Working hours'));
      await tester.pumpAndSettle();

      final mondaySwitch = find.descendant(
        of: find.ancestor(of: find.text('Monday'), matching: find.byType(Row)).first,
        matching: find.byType(FSwitch),
      );
      final switchWidget = tester.widget<FSwitch>(mondaySwitch);
      if (!switchWidget.value) {
        await tester.tap(mondaySwitch);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('create branch modal dismiss on scrim tap', (tester) async {
      await pumpWithModal(tester);

      expect(find.text('Add branch'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Add branch'), findsNothing);
    });

    testWidgets('create branch validates required fields', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpWithModal(tester, rpcClient: rpcClient);

      await tester.tap(find.widgetWithText(AppButton, 'Create branch'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, isNull);
      expect(find.text('Branch name *'), findsOneWidget);
    });

    testWidgets('create branch success closes modal and calls RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpWithModal(tester, rpcClient: rpcClient);
      await fillValidBranchForm(tester);

      final createButton = find.widgetWithText(AppButton, 'Create branch');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'manage_create_branch');
      expect(find.text('Add branch'), findsNothing);
    });

    testWidgets('stupid usage: double-tap Create branch sends single RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpWithModal(tester, rpcClient: rpcClient);
      await fillValidBranchForm(tester);

      final createButton = find.widgetWithText(AppButton, 'Create branch');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(rpcClient.rpcCalls.where((call) => call.function == 'manage_create_branch').length, 1);
    });

    testWidgets('keyboard Enter submits create branch modal', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await pumpWithModal(tester, rpcClient: rpcClient);
      await fillValidBranchForm(tester);

      await tester.tap(find.widgetWithText(AppTextField, 'Branch name *'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(rpcClient.rpcCalls.where((call) => call.function == 'manage_create_branch').length, 1);
      expect(find.text('Add branch'), findsNothing);
    });
  });
}
