import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_list_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('BranchListPage', () {
    testWidgets('shows active branches with filter chips', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('New branch'), findsOneWidget);
    });

    testWidgets('inactive filter shows only inactive branches', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('Closed Wing'), findsOneWidget);
      expect(find.text('Main Branch'), findsNothing);
    });

    testWidgets('user without permission sees denial message', (tester) async {
      await tester.pumpWidget(_host(hasPermission: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
      expect(find.text('New branch'), findsNothing);
    });

    testWidgets('LAST_ACTIVE_BRANCH shows edit shortcut dialog', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'set_branch_active': {
            'success': false,
            'error_code': 'LAST_ACTIVE_BRANCH',
            'error_message': 'Cannot deactivate the last active branch.',
          },
        },
      );
      await tester.pumpWidget(_host(rpcClient: rpcClient, singleActiveBranch: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot deactivate branch'), findsOneWidget);
      expect(find.text('Edit branch'), findsOneWidget);
    });

    testWidgets('stupid usage: empty list shows helpful empty state', (tester) async {
      await tester.pumpWidget(_host(empty: true));
      await tester.pumpAndSettle();

      expect(find.text('No active branches.'), findsOneWidget);
    });

    testWidgets('reactivate inactive branch succeeds', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

Widget _host({
  bool hasPermission = true,
  bool includeInactive = false,
  bool singleActiveBranch = false,
  bool empty = false,
  SettingsRpcTestClient? rpcClient,
}) {
  final branches = <Map<String, dynamic>>[
    if (!empty)
      {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': 'Main Branch',
        'code': 'main',
        'is_active': true,
        'is_deleted': false,
        'organization_id': '00000000-0000-4000-8000-000000000020',
      },
    if (includeInactive && !empty)
      {
        'id': '00000000-0000-4000-8000-000000000099',
        'name': 'Closed Wing',
        'code': 'closed',
        'is_active': false,
        'is_deleted': false,
        'organization_id': '00000000-0000-4000-8000-000000000020',
      },
  ];

  if (singleActiveBranch) {
    branches
      ..clear()
      ..add({
        'id': '00000000-0000-4000-8000-000000000001',
        'name': 'Main Branch',
        'is_active': true,
        'is_deleted': false,
        'organization_id': '00000000-0000-4000-8000-000000000020',
      });
  }

  final tableClient = SettingsTableTestClient({'branches': branches});
  final rpcRepo = BranchRepositoryImpl(rpcClient ?? SettingsRpcTestClient());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: hasPermission ? {'settings.manage_branches'} : {'patients.view'},
            ),
          ),
        ),
      ),
      branchRepositoryProvider.overrideWithValue(_TableBranchRepository(tableClient, rpcRepo)),
    ],
    child: const MaterialApp(home: BranchListPage()),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _TableBranchRepository extends BranchRepositoryImpl {
  _TableBranchRepository(this._tableClient, this._rpcRepo) : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final BranchRepositoryImpl _rpcRepo;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) {
    return BranchRepositoryImpl(_tableClient).listBranches(organizationId: organizationId, filter: filter);
  }

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) {
    return _rpcRepo.setBranchActive(branchId: branchId, isActive: isActive);
  }
}
