import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_form_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/branch_form_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  const branchId = '00000000-0000-4000-8000-000000000001';

  group('BranchFormPage', () {
    testWidgets('create mode shows editable fields', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('New branch'), findsOneWidget);
      expect(find.text('Create branch'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(find.text('Modify'), findsNothing);
    });

    testWidgets('edit mode shows stored values with Modify', (tester) async {
      await tester.pumpWidget(_host(branchId: branchId));
      await tester.pumpAndSettle();

      expect(find.text('Edit branch'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('1 Main St'), findsOneWidget);
      expect(find.text('Modify'), findsNWidgets(5));
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('stupid usage: empty name blocked on save', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create branch'));
      await tester.pumpAndSettle();

      expect(find.text('Branch name is required.'), findsOneWidget);
    });

    testWidgets('create branch invokes manage_create_branch RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(rpcClient: rpcClient));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'North Clinic');
      await tester.tap(find.text('Create branch'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'manage_create_branch');
      expect(rpcClient.lastParams, containsPair('p_name', 'North Clinic'));
    });

    testWidgets('advanced: DUPLICATE_CODE shows field error', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'manage_create_branch': {'success': false, 'error_code': 'DUPLICATE_CODE', 'error_message': 'Duplicate'},
        },
      );
      await tester.pumpWidget(_host(rpcClient: rpcClient));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Branch X');
      await tester.enterText(find.byType(TextFormField).at(1), 'MAIN');
      await tester.tap(find.text('Create branch'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already uses this code'), findsWidgets);
    });

    testWidgets('corner case: missing branch id in edit shows not-found message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(permissions: {'settings.manage_branches'}),
                ),
              ),
            ),
            branchFormProvider('missing-id').overrideWith(() => _MissingBranchFormNotifier()),
          ],
          child: const MaterialApp(home: BranchFormPage(branchId: 'missing-id')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not found'), findsOneWidget);
    });

    testWidgets('user without permission sees denial', (tester) async {
      await tester.pumpWidget(_host(hasPermission: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
    });

    testWidgets('Modify branch name opens editor in edit mode', (tester) async {
      await tester.pumpWidget(_host(branchId: branchId));
      await tester.pumpAndSettle();

      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.text('Modify').first);
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Main Branch'), findsOneWidget);
    });
  });
}

Widget _host({String? branchId, bool hasPermission = true, SettingsRpcTestClient? rpcClient}) {
  final branches = [
    {
      'id': '00000000-0000-4000-8000-000000000001',
      'name': 'Main Branch',
      'code': 'main',
      'address': '1 Main St',
      'is_active': true,
      'is_deleted': false,
      'organization_id': '00000000-0000-4000-8000-000000000020',
    },
  ];

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
      branchRepositoryProvider.overrideWithValue(_FormBranchRepository(tableClient, rpcRepo)),
    ],
    child: MaterialApp(home: BranchFormPage(branchId: branchId)),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _MissingBranchFormNotifier extends BranchFormNotifier {
  _MissingBranchFormNotifier() : super('missing-id');

  @override
  Future<BranchFormUiState> build() async {
    return const BranchFormUiState(
      errorMessage: 'Branch missing-id was not found. Return to the branch list and try again.',
    );
  }
}

class _FormBranchRepository extends BranchRepositoryImpl {
  _FormBranchRepository(this._tableClient, this._rpcRepo) : super(_tableClient);

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
  Future<String> createBranch(CreateBranchInput input) => _rpcRepo.createBranch(input);

  @override
  Future<String> updateBranch(UpdateBranchInput input) => _rpcRepo.updateBranch(input);
}
