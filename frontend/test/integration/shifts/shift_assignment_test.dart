// US3 acceptance scenarios 1–5 (assignment panel with fake RPC).
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_detail_page.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

const _branchId = '44444444-4444-4444-8444-444444444444';
const _staffId = '22222222-2222-4222-8222-222222222222';
const _secondStaffId = ShiftRpcTestClient.secondStaffId;
const _shiftId = ShiftRpcTestClient.defaultShiftId;

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? {PermissionKeys.shiftsManage},
      activeBranchId: _branchId,
      branchIds: [_branchId],
    ),
  );
}

Widget _host({ShiftRpcTestClient? client, AuthSessionState? auth}) {
  final rpcClient = client ?? ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      supabaseClientProvider.overrideWithValue(rpcClient),
      shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(rpcClient)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '${AppRoutes.shifts}/$_shiftId',
        routes: [
          GoRoute(
            path: '${AppRoutes.shifts}/:id',
            builder: (_, state) => ShiftDetailPage(shiftId: state.pathParameters['id']),
          ),
        ],
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'US')],
    ),
  );
}

void main() {
  group('Shift assignment US3 integration', () {
    testWidgets('scenario 1: add eligible staff calls RPC and shows new assignee', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        expect(find.byKey(const Key('shift_detail_assignment_panel')), findsOneWidget);
        expect(find.byKey(Key('shift_detail_assignee_$_secondStaffId')), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byKey(Key('shift_staff_option_$_secondStaffId')), findsOneWidget);
        await tester.tap(find.byKey(Key('shift_staff_option_$_secondStaffId')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift_detail_add_staff_submit')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('modify_shift_assignments'));
        expect(client.paramsFor('modify_shift_assignments')?['p_add_staff_ids'], [_secondStaffId]);
        expect(find.byKey(Key('shift_detail_assignee_$_secondStaffId')), findsOneWidget);
        expect(find.byKey(Key('shift_detail_assignee_$_staffId')), findsOneWidget);
      });
    });

    testWidgets('scenario 2: remove one of many keeps remaining assignee', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..detailAssignments = [
            {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'staff_member_id': _staffId, 'display_name': 'Dr Shift'},
            {
              'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'staff_member_id': _secondStaffId,
              'display_name': 'Nurse Shift',
            },
          ];

        await _pumpHost(tester, _host(client: client));

        await tester.tap(find.byKey(Key('shift_detail_remove_assignee_$_secondStaffId')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift_detail_confirm_remove')));
        await tester.pumpAndSettle();

        expect(client.paramsFor('modify_shift_assignments')?['p_remove_staff_ids'], [_secondStaffId]);
        expect(find.byKey(Key('shift_detail_assignee_$_staffId')), findsOneWidget);
        expect(find.byKey(Key('shift_detail_assignee_$_secondStaffId')), findsNothing);
      });
    });

    testWidgets('scenario 3: overlap on add shows conflict banner', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..modifyAssignmentsException = const PostgrestException(
            message:
                'shift_overlap: [{"staff_member_id":"$_secondStaffId","display_name":"Nurse Shift","conflicting_shift_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","start_time":"09:00","end_time":"17:00"}]',
            code: 'P0001',
          );

        await _pumpHost(tester, _host(client: client));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('shift_staff_option_$_secondStaffId')), findsOneWidget);
        await tester.tap(find.byKey(Key('shift_staff_option_$_secondStaffId')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift_detail_add_staff_submit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shift_conflict_banner')), findsOneWidget);
        expect(find.textContaining('Nurse Shift is already scheduled 09:00–17:00'), findsOneWidget);
      });
    });

    testWidgets('scenario 4: remove last assignee shows unassigned state', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await tester.tap(find.byKey(Key('shift_detail_remove_assignee_$_staffId')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift_detail_confirm_remove')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shift_detail_unassigned')), findsOneWidget);
      });
    });

    testWidgets('scenario 5: user without shifts.manage sees no assignment controls', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        await _pumpHost(tester, _host(auth: _auth(permissions: const {})));

        expect(find.byKey(const Key('shift_detail_assignment_panel')), findsNothing);
        expect(find.byKey(Key('shift_detail_remove_assignee_$_staffId')), findsNothing);
        expect(find.byKey(const Key('shift_detail_read_only_banner')), findsOneWidget);
      });
    });
  });
}
