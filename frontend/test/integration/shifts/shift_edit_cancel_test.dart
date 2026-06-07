// US4 acceptance scenarios 1–6 (edit/cancel with fake RPC).
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

Widget _host({
  ShiftRpcTestClient? client,
  AuthSessionState? auth,
  String initialLocation = '${AppRoutes.shifts}/$_shiftId',
}) {
  final rpcClient = client ?? ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      supabaseClientProvider.overrideWithValue(rpcClient),
      shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(rpcClient)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: AppRoutes.shiftsCalendar,
            builder: (_, _) => const Scaffold(body: Text('Shift calendar')),
          ),
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
  group('Shift edit/cancel US4 integration', () {
    testWidgets('scenario 1: manager updates shift end time via update_shift RPC', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await tester.tap(find.byKey(const Key('shift_detail_edit_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('shift_notes_field')), 'Evening coverage');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift_detail_edit_save')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('update_shift'));
        expect(client.paramsFor('update_shift')?['p_shift_id'], _shiftId);
        expect(find.textContaining('Shift updated successfully'), findsOneWidget);
      });
    });

    testWidgets('scenario 2: overlap on save shows conflict banner and preserves values', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..updateShiftException = PostgrestException(
            message:
                'shift_overlap: [{"staff_member_id":"$_staffId","display_name":"Dr Shift","conflicting_shift_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","start_time":"09:00","end_time":"17:00"}]',
            code: 'P0001',
          );

        await _pumpHost(tester, _host(client: client));
        await tester.tap(find.byKey(const Key('shift_detail_edit_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shift_detail_edit_save')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shift_conflict_banner')), findsOneWidget);
        expect(find.textContaining('17:00'), findsWidgets);
        expect(client.detailEndTime, '17:00');
      });
    });

    testWidgets('scenario 3: cancel shift confirms and navigates to calendar', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await tester.tap(find.byKey(const Key('shift_detail_cancel_shift_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel_shift_dialog_confirm')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('cancel_shift'));
        expect(client.shiftCancelled, isTrue);
        expect(find.text('Shift calendar'), findsOneWidget);
      });
    });

    testWidgets('scenario 4: cancelled shift shows read-only banner without edit controls', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..shiftCancelled = true
          ..getShiftDetailOverride = {
            'shift': {
              'id': _shiftId,
              'branch_id': _branchId,
              'shift_date': '2026-06-10',
              'start_time': '09:00',
              'end_time': '17:00',
              'notes': null,
              'status': 'cancelled',
              'is_unassigned': false,
              'is_past': false,
              'is_read_only': true,
              'updated_at': DateTime.utc(2026, 6, 1, 10).toIso8601String(),
            },
            'assignments': [
              {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'staff_member_id': _staffId, 'display_name': 'Dr Shift'},
            ],
            'branch': {'id': _branchId, 'name': 'Main Branch', 'code': 'MAIN'},
          };

        await _pumpHost(tester, _host(client: client));

        expect(find.byKey(const Key('shift_detail_read_only_banner')), findsOneWidget);
        expect(find.textContaining('cancelled'), findsWidgets);
        expect(find.byKey(const Key('shift_detail_edit_button')), findsNothing);
        expect(find.byKey(const Key('shift_detail_cancel_shift_button')), findsNothing);
      });
    });

    testWidgets('scenario 5: user without shifts.manage sees read-only detail', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        await _pumpHost(tester, _host(auth: _auth(permissions: {})));

        expect(find.byKey(const Key('shift_detail_read_only_banner')), findsOneWidget);
        expect(find.byKey(const Key('shift_detail_edit_button')), findsNothing);
        expect(find.byKey(const Key('shift_detail_cancel_shift_button')), findsNothing);
        expect(find.byKey(const Key('shift_detail_assignment_panel')), findsNothing);
      });
    });

    testWidgets('scenario 6: past-date shift is read-only for manager', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..getShiftDetailOverride = {
            'shift': {
              'id': _shiftId,
              'branch_id': _branchId,
              'shift_date': '2026-06-01',
              'start_time': '09:00',
              'end_time': '17:00',
              'notes': null,
              'status': 'active',
              'is_unassigned': false,
              'is_past': true,
              'is_read_only': true,
              'updated_at': DateTime.utc(2026, 6, 1, 10).toIso8601String(),
            },
            'assignments': [
              {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'staff_member_id': _staffId, 'display_name': 'Dr Shift'},
            ],
            'branch': {'id': _branchId, 'name': 'Main Branch', 'code': 'MAIN'},
          };

        await _pumpHost(tester, _host(client: client));

        expect(find.byKey(const Key('shift_detail_read_only_banner')), findsOneWidget);
        expect(find.textContaining('Past shifts'), findsOneWidget);
        expect(find.byKey(const Key('shift_detail_edit_button')), findsNothing);
      });
    });
  });
}
