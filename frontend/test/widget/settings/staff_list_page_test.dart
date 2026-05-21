import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('StaffListPage', () {
    testWidgets('shows active staff with filter chips', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Dr. Smith'), findsOneWidget);
      expect(find.text('New staff'), findsOneWidget);
    });

    testWidgets('inactive filter shows only inactive staff', (tester) async {
      await tester.pumpWidget(_host(includeInactive: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('Former Receptionist'), findsOneWidget);
      expect(find.text('Dr. Smith'), findsNothing);
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

      expect(find.text('No active staff members.'), findsOneWidget);
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

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

Widget _host({
  bool hasPermission = true,
  bool includeInactive = false,
  bool empty = false,
  SettingsRpcTestClient? rpcClient,
}) {
  final staff = <Map<String, dynamic>>[
    if (!empty)
      {
        'id': '00000000-0000-4000-8000-000000000101',
        'full_name': 'Dr. Smith',
        'role': 'doctor',
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
  ];

  final tableClient = SettingsTableTestClient({'staff_members': staff});
  final rpcRepo = StaffAdminRepository(rpcClient ?? SettingsRpcTestClient());

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
      staffAdminRepositoryProvider.overrideWithValue(_FakeStaffAdminRepository(tableClient, rpcRepo)),
    ],
    child: const MaterialApp(home: StaffListPage()),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _FakeStaffAdminRepository extends StaffAdminRepository {
  _FakeStaffAdminRepository(this._tableClient, this._rpcRepo) : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final StaffAdminRepository _rpcRepo;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    final base = _tableClient
        .from('staff_members')
        .select('id, full_name, role, phone, is_active')
        .eq('is_deleted', false);
    final List<dynamic> rows;
    switch (filter) {
      case StaffListFilter.active:
        rows = await base.eq('is_active', true).order('full_name');
      case StaffListFilter.inactive:
        rows = await base.eq('is_active', false).order('full_name');
      case StaffListFilter.all:
        rows = await base.order('full_name');
    }
    final items = <StaffListItem>[];
    for (final row in rows) {
      final item = StaffListItem.fromRow(Map<String, dynamic>.from(row));
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return _rpcRepo.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }
}
