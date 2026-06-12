import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_member_card.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('StaffListPage', () {
    testWidgets('shows staff member cards', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.byType(StaffMemberCard), findsOneWidget);
      expect(find.text('Dr. Smith'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('New staff'), findsOneWidget);
    });

    testWidgets('staff cards are sorted alphabetically by name', (tester) async {
      await tester.pumpWidget(
        _host(
          extraStaff: const [
            {
              'id': '00000000-0000-4000-8000-000000000103',
              'full_name': 'Alice Admin',
              'role': 'administrator',
              'is_active': true,
              'is_deleted': false,
            },
            {
              'id': '00000000-0000-4000-8000-000000000104',
              'full_name': 'Zoe Nurse',
              'role': 'lab_staff',
              'is_active': true,
              'is_deleted': false,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<StaffMemberCard>(find.byType(StaffMemberCard))
          .map((card) => card.member.fullName)
          .toList();
      expect(names, ['Alice Admin', 'Dr. Smith', 'Zoe Nurse']);
    });

    testWidgets('single staff card uses one third of grid width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(embedded: true));
      await tester.pumpAndSettle();

      final cardBox = tester.renderObject<RenderBox>(find.byType(StaffMemberCard));
      final gridBox = tester.renderObject<RenderBox>(find.byType(SettingsCardsGrid));
      final expectedThirdWidth = (gridBox.size.width - (2 * SpacingTokens.lg)) / 3;

      expect(cardBox.size.width, closeTo(expectedThirdWidth, 1));
    });

    testWidgets('shows all staff including inactive members', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Smith'), findsOneWidget);
      expect(find.text('Former Receptionist'), findsOneWidget);
    });

    testWidgets('user without permission sees denial message', (tester) async {
      await tester.pumpWidget(_host(hasPermission: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
      expect(find.text('New staff'), findsNothing);
    });

    testWidgets('stupid usage: empty list shows helpful empty state', (tester) async {
      await tester.pumpWidget(_host(empty: true));
      await tester.pumpAndSettle();

      expect(find.text('No staff yet. Create an account to get started.'), findsOneWidget);
    });

    testWidgets('highlights primary branch on card', (tester) async {
      await tester.pumpWidget(
        _host(
          branches: const {
            '00000000-0000-4000-8000-000000000101': [
              StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true),
              StaffBranchLabel(id: '00000000-0000-4000-8000-000000000202', name: 'East Wing'),
            ],
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Clinic'), findsOneWidget);
      expect(find.text('East Wing'), findsOneWidget);
    });

    testWidgets('deactivate confirms before calling RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(rpcClient: rpcClient));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate staff member?'), findsOneWidget);
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'set_staff_active');
      expect(rpcClient.lastParams, containsPair('p_is_active', false));
    });

    testWidgets('advanced: RPC failure shows snackbar', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'set_staff_active': {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Not allowed'},
        },
      );
      await tester.pumpWidget(_host(rpcClient: rpcClient));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('permission'), findsOneWidget);
    });

    testWidgets('regression: reactivate inactive staff succeeds', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      final inactiveCard = find.ancestor(of: find.text('Former Receptionist'), matching: find.byType(StaffMemberCard));
      await tester.tap(find.descendant(of: inactiveCard, matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('embedded mode omits scaffold app bar', (tester) async {
      await tester.pumpWidget(_host(embedded: true));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('New staff'), findsOneWidget);
    });

    testWidgets('new staff opens blurred create modal', (tester) async {
      await tester.pumpWidget(_host(embedded: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New staff'));
      await tester.pumpAndSettle();

      expect(find.text('New staff member'), findsOneWidget);
      expect(find.text('Create staff account'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('staff cards stay sorted alphabetically after clearing search', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(
          extraStaff: const [
            {
              'id': '00000000-0000-4000-8000-000000000103',
              'full_name': 'Alice Admin',
              'role': 'administrator',
              'is_active': true,
              'is_deleted': false,
            },
            {
              'id': '00000000-0000-4000-8000-000000000104',
              'full_name': 'Zoe Nurse',
              'role': 'lab_staff',
              'is_active': true,
              'is_deleted': false,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Smith');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<StaffMemberCard>(find.byType(StaffMemberCard))
          .map((card) => card.member.fullName)
          .toList();
      expect(names, ['Alice Admin', 'Dr. Smith', 'Zoe Nurse']);

      final cardsByName = <String, RenderBox>{
        for (final card in tester.widgetList<StaffMemberCard>(find.byType(StaffMemberCard)))
          card.member.fullName: tester.renderObject<RenderBox>(
            find.widgetWithText(StaffMemberCard, card.member.fullName),
          ),
      };
      expect(
        cardsByName['Alice Admin']!.localToGlobal(Offset.zero).dx,
        lessThan(cardsByName['Dr. Smith']!.localToGlobal(Offset.zero).dx),
      );
      expect(
        cardsByName['Dr. Smith']!.localToGlobal(Offset.zero).dx,
        lessThan(cardsByName['Zoe Nurse']!.localToGlobal(Offset.zero).dx),
      );
    });

    testWidgets('staff cards stay sorted when search is cleared during fade-out', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(
          extraStaff: const [
            {
              'id': '00000000-0000-4000-8000-000000000103',
              'full_name': 'Alice Admin',
              'role': 'administrator',
              'is_active': true,
              'is_deleted': false,
            },
            {
              'id': '00000000-0000-4000-8000-000000000104',
              'full_name': 'Zoe Nurse',
              'role': 'lab_staff',
              'is_active': true,
              'is_deleted': false,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Smith');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<StaffMemberCard>(find.byType(StaffMemberCard))
          .map((card) => card.member.fullName)
          .toList();
      expect(names, ['Alice Admin', 'Dr. Smith', 'Zoe Nurse']);
    });

    testWidgets('search filters staff by name', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Former');
      await tester.pumpAndSettle();

      expect(find.text('Former Receptionist'), findsOneWidget);
      expect(find.text('Dr. Smith'), findsNothing);
    });

    testWidgets('filter popover opens with branch and role controls', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Roles'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('filter dropdown close button dismisses branch menu', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('All branches'));
      await tester.pumpAndSettle();

      expect(find.text('Main Clinic'), findsOneWidget);

      final closeButtons = find.byTooltip('Close');
      expect(closeButtons, findsWidgets);

      await tester.tap(closeButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Main Clinic'), findsNothing);
      expect(find.text('Filters'), findsOneWidget);
    });
  });
}

Widget _host({
  bool hasPermission = true,
  bool includeInactive = false,
  bool empty = false,
  bool embedded = false,
  List<Map<String, dynamic>> extraStaff = const [],
  Map<String, List<StaffBranchLabel>>? branches,
  SettingsRpcTestClient? rpcClient,
}) {
  final staff = <Map<String, dynamic>>[
    if (!empty)
      {
        'id': '00000000-0000-4000-8000-000000000101',
        'full_name': 'Dr. Smith',
        'role': 'doctor',
        'phone': '(603) 555-0123',
        'is_active': true,
        'is_deleted': false,
      },
    if (includeInactive && !empty)
      {
        'id': '00000000-0000-4000-8000-000000000102',
        'full_name': 'Former Receptionist',
        'role': 'receptionist',
        'is_active': false,
        'is_deleted': false,
      },
    ...extraStaff,
  ];

  final tableClient = SettingsTableTestClient({'staff_members': staff});
  final rpcRepo = StaffAdminRepositoryImpl(rpcClient ?? SettingsRpcTestClient());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: hasPermission ? {'settings.manage_staff'} : {'patients.view'},
            ),
          ),
        ),
      ),
      staffAdminRepositoryProvider.overrideWithValue(
        _FakeStaffAdminRepository(tableClient, rpcRepo, branches: branches),
      ),
      staffAssignableBranchesProvider.overrideWith(
        (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
      ),
      clinicSetupBranchesProvider.overrideWith(
        (ref) async => const [
          BranchListItem(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isActive: true),
        ],
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: StaffListPage(embedded: embedded),
    ),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _FakeStaffAdminRepository extends StaffAdminRepositoryImpl {
  _FakeStaffAdminRepository(this._tableClient, this._rpcRepo, {this.branches, this.usernames}) : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final StaffAdminRepositoryImpl _rpcRepo;
  final Map<String, List<StaffBranchLabel>>? branches;
  final Map<String, String>? usernames;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    final base = _tableClient
        .from('staff_members')
        .select('id, full_name, role, phone, is_active')
        .eq('is_deleted', false);
    final List<dynamic> rows;
    switch (filter) {
      case StaffListFilter.active:
        rows = await base.eq('is_active', true).order('full_name', ascending: true);
      case StaffListFilter.inactive:
        rows = await base.eq('is_active', false).order('full_name', ascending: true);
      case StaffListFilter.all:
        rows = await base.order('full_name', ascending: true);
    }
    final items = <StaffListItem>[];
    for (final row in rows) {
      final item = StaffListItem.fromRow(Map<String, dynamic>.from(row));
      if (item != null) {
        items.add(item.copyWith(branches: branches?[item.id] ?? const [], username: usernames?[item.id]));
      }
    }
    items.sort(StaffListItem.compareByFullName);
    return items;
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return _rpcRepo.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }
}
