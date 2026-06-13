import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/animated_filter_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_member_card.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
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

    testWidgets('active staff card shows status icon only', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byTooltip('Active staff member'), findsOneWidget);
      expect(find.byTooltip('Deactivate staff member'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });

    testWidgets('inactive staff card shows inactive status icon only', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      final inactiveCard = find.ancestor(of: find.text('Former Receptionist'), matching: find.byType(StaffMemberCard));
      expect(find.descendant(of: inactiveCard, matching: find.byIcon(Icons.pause_circle_outline)), findsOneWidget);
      expect(find.descendant(of: inactiveCard, matching: find.byTooltip('Inactive staff member')), findsOneWidget);
      expect(find.descendant(of: inactiveCard, matching: find.byTooltip('Activate staff member')), findsNothing);
      expect(
        find.descendant(of: inactiveCard, matching: find.byTooltip('Delete staff member permanently')),
        findsNothing,
      );
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

    testWidgets('tapping staff card opens detail sheet', (tester) async {
      await tester.pumpWidget(_host(usernames: const {'00000000-0000-4000-8000-000000000101': 'drsmith'}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dr. Smith'));
      await tester.pumpAndSettle();

      expect(find.text('Login credentials'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsWidgets);
      expect(find.byTooltip('Deactivate staff member'), findsWidgets);
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

    testWidgets('apply branch filter restricts list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const eastWingDoctor = StaffListItem(
        id: '00000000-0000-4000-8000-000000000103',
        fullName: 'East Wing Doctor',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000202', name: 'East Wing', isPrimary: true)],
      );
      const mainClinicDoctor = StaffListItem(
        id: '00000000-0000-4000-8000-000000000101',
        fullName: 'Dr. Smith',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
      );

      const query = StaffListQuery(branchIds: {'00000000-0000-4000-8000-000000000201'});
      expect(query.matches(mainClinicDoctor), isTrue);
      expect(query.matches(eastWingDoctor), isFalse);
    });

    testWidgets('apply role filter restricts list', (tester) async {
      const doctor = StaffListItem(id: '1', fullName: 'Dr. Smith', role: StaffRole.doctor, isActive: true);
      const receptionist = StaffListItem(
        id: '2',
        fullName: 'Former Receptionist',
        role: StaffRole.receptionist,
        isActive: false,
      );

      const query = StaffListQuery(roles: {StaffRole.doctor});
      expect(query.matches(doctor), isTrue);
      expect(query.matches(receptionist), isFalse);
    });

    testWidgets('clear all filters resets to full list', (tester) async {
      const query = StaffListQuery(roles: {StaffRole.doctor}, branchIds: {'branch-1'});
      final cleared = query.copyWith(roles: {}, branchIds: {});
      expect(cleared.activeFilterCount, 0);
      expect(cleared.roles, isEmpty);
      expect(cleared.branchIds, isEmpty);
    });

    testWidgets('stupid usage: search special characters', (tester) async {
      await tester.pumpWidget(
        _host(
          extraStaff: const [
            {
              'id': '00000000-0000-4000-8000-000000000105',
              'full_name': 'Dr. %Wildcard',
              'role': 'doctor',
              'is_active': true,
              'is_deleted': false,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      for (final query in ['%', '_', '😀']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('very long staff name truncates gracefully on card', (tester) async {
      final longName = 'A' * 200;
      await tester.pumpWidget(
        _host(
          extraStaff: [
            {
              'id': '00000000-0000-4000-8000-000000000106',
              'full_name': longName,
              'role': 'doctor',
              'is_active': true,
              'is_deleted': false,
            },
          ],
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.renderObject<RenderBox>(find.text(longName));
      final screen = tester.renderObject<RenderBox>(find.byType(StaffListPage));
      expect(card.size.width, lessThanOrEqualTo(screen.size.width));
    });

    testWidgets('animated filter cards grid fade', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedFilterCardsGrid<StaffListItem>), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Former');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Former Receptionist'), findsOneWidget);
      expect(find.text('Dr. Smith'), findsNothing);
    });

    testWidgets('animated filter grid disposal safe when page closes mid-animation', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Former');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
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
  Map<String, String>? usernames,
  SettingsRpcTestClient? rpcClient,
  List<BranchListItem>? clinicBranches,
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
        _FakeStaffAdminRepository(tableClient, rpcRepo, branches: branches, usernames: usernames),
      ),
      staffAssignableBranchesProvider.overrideWith(
        (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
      ),
      clinicSetupBranchesProvider.overrideWith(
        (ref) async =>
            clinicBranches ??
            const [BranchListItem(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isActive: true)],
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
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async {
    final row = await _tableClient
        .from('staff_members')
        .select('id, full_name, role, phone, is_active')
        .eq('id', staffMemberId)
        .eq('is_deleted', false)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final item = StaffListItem.fromRow(Map<String, dynamic>.from(row));
    if (item == null) {
      return null;
    }

    final branchLabels = branches?[staffMemberId] ?? const <StaffBranchLabel>[];
    final branchIds = [
      for (final branch in branchLabels)
        if (branch.id != null) branch.id!,
    ];
    final primaryBranchId = branchLabels.where((branch) => branch.isPrimary).map((branch) => branch.id).firstOrNull;

    return StaffMemberDetail(
      id: item.id,
      fullName: item.fullName,
      role: item.role,
      isActive: item.isActive,
      phone: item.phone,
      username: usernames?[staffMemberId],
      branchIds: branchIds,
      primaryBranchId: primaryBranchId ?? (branchIds.length == 1 ? branchIds.first : null),
    );
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return _rpcRepo.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) {
    return _rpcRepo.deleteStaffMember(staffMemberId: staffMemberId);
  }
}
