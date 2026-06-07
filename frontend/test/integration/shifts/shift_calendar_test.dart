// US2 acceptance scenarios 1–7 (calendar + read-only detail with fake RPC).
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_calendar_page.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_detail_page.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_month_day_sheet.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

const _branchId = '44444444-4444-4444-8444-444444444444';
const _shiftActiveId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _shiftIncompleteId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _shiftMorningId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _shiftAfternoonId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

List<Map<String, dynamic>> _sampleWeekShifts({bool includeCancelled = false}) {
  return [
    {
      'id': _shiftActiveId,
      'branch_id': _branchId,
      'shift_date': '2026-06-10',
      'start_time': '09:00',
      'end_time': '17:00',
      'status': 'active',
      'is_unassigned': false,
      'assignee_names': ['Dr Shift'],
      'assignee_count': 1,
      'notes_preview': null,
    },
    {
      'id': _shiftIncompleteId,
      'branch_id': _branchId,
      'shift_date': '2026-06-11',
      'start_time': '08:00',
      'end_time': '12:00',
      'status': 'incomplete',
      'is_unassigned': true,
      'assignee_names': <String>[],
      'assignee_count': 0,
      'notes_preview': null,
    },
    if (includeCancelled)
      {
        'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'branch_id': _branchId,
        'shift_date': '2026-06-12',
        'start_time': '09:00',
        'end_time': '17:00',
        'status': 'cancelled',
        'is_unassigned': false,
        'assignee_names': ['Dr Shift'],
        'assignee_count': 1,
        'notes_preview': null,
      },
  ];
}

List<Map<String, dynamic>> _multiShiftDayPayload() {
  return [
    {
      'id': _shiftMorningId,
      'branch_id': _branchId,
      'shift_date': '2026-06-10',
      'start_time': '08:00',
      'end_time': '12:00',
      'status': 'active',
      'is_unassigned': false,
      'assignee_names': ['Dr A'],
      'assignee_count': 1,
      'notes_preview': null,
    },
    {
      'id': _shiftAfternoonId,
      'branch_id': _branchId,
      'shift_date': '2026-06-10',
      'start_time': '13:00',
      'end_time': '17:00',
      'status': 'incomplete',
      'is_unassigned': true,
      'assignee_names': <String>[],
      'assignee_count': 0,
      'notes_preview': null,
    },
  ];
}

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
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

Widget _host({ShiftRpcTestClient? client, AuthSessionState? auth, String initialLocation = AppRoutes.shiftsCalendar}) {
  final rpcClient = client ?? ShiftRpcTestClient(branchId: _branchId);

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
          GoRoute(path: AppRoutes.shiftsCalendar, builder: (_, _) => const ShiftCalendarPage()),
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
  group('Shift calendar US2 integration', () {
    testWidgets('scenario 1: branch staff see shifts with times and assignee summary', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)..listShiftsPayload = _sampleWeekShifts();
        await _pumpHost(
          tester,
          _host(
            client: client,
            auth: _auth(permissions: {PermissionKeys.patientsView}),
          ),
        );

        final container = ProviderScope.containerOf(tester.element(find.byType(ShiftCalendarPage)));
        final calendarState = container.read(shiftCalendarProvider);
        expect(calendarState.items, hasLength(2));
        expect(calendarState.items.first.assigneeSummary, 'Dr Shift');
        expect(calendarState.items.last.isUnassigned, isTrue);

        expect(client.rpcLog, contains('list_shifts'));
        expect(find.byKey(const Key('shift_calendar_create_fab')), findsNothing);
        expect(find.byKey(const Key('shift_calendar_mode_toggle')), findsOneWidget);
      });
    });

    testWidgets('scenario 2a: switching to month mode refetches and renders without framework errors', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)..listShiftsPayload = _sampleWeekShifts();
        await _pumpHost(tester, _host(client: client));

        client.rpcLog.clear();
        await tester.tap(find.text('Month'));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('list_shifts'));
        expect(find.byKey(const Key('shift_calendar_loading')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('scenario 2: week navigation refetches adjacent week', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)..listShiftsPayload = _sampleWeekShifts();
        await _pumpHost(tester, _host(client: client));

        client.rpcLog.clear();
        await tester.tap(find.byKey(const Key('shift_calendar_next')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('list_shifts'));
        expect(client.lastParams?['p_branch_id'], _branchId);
      });
    });

    testWidgets('scenario 3: month day sheet lists multiple shifts for one day', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () {
                        ShiftMonthDaySheet.show(
                          context,
                          date: DateTime(2026, 6, 10),
                          shifts: _multiShiftDayPayload()
                              .map((row) => ShiftListItem.fromRow(row))
                              .whereType<ShiftListItem>()
                              .toList(growable: false),
                        );
                      },
                      child: const Text('Open day'),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open day'));
        await tester.pumpAndSettle();

        expect(find.byKey(Key('shift_month_day_item_$_shiftMorningId')), findsOneWidget);
        expect(find.byKey(Key('shift_month_day_item_$_shiftAfternoonId')), findsOneWidget);
        expect(find.text('08:00–12:00'), findsOneWidget);
        expect(find.text('13:00–17:00'), findsOneWidget);
      });
    });

    testWidgets('scenario 4: cancelled shifts from RPC are excluded like backend list_shifts', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)
          ..listShiftsPayload = _sampleWeekShifts(includeCancelled: true);
        await _pumpHost(tester, _host(client: client));

        expect(client.listShiftsPayload.length, 3);
        final container = ProviderScope.containerOf(tester.element(find.byType(ShiftCalendarPage)));
        expect(container.read(shiftCalendarProvider).items, hasLength(2));
      });
    });

    testWidgets('scenario 5: read-only users see read-only detail banner', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)
          ..getShiftDetailOverride = {
            'shift': {
              'id': _shiftActiveId,
              'branch_id': _branchId,
              'shift_date': '2026-06-10',
              'start_time': '09:00',
              'end_time': '17:00',
              'notes': null,
              'status': 'active',
              'is_unassigned': false,
              'is_past': false,
              'is_read_only': true,
              'updated_at': '2026-06-01T10:00:00.000Z',
            },
            'assignments': [
              {
                'id': '11111111-1111-4111-8111-111111111111',
                'staff_member_id': '22222222-2222-4222-8222-222222222222',
                'display_name': 'Dr Shift',
              },
            ],
            'branch': {'id': _branchId, 'name': 'Main Branch', 'code': 'MAIN'},
          };

        await _pumpHost(
          tester,
          _host(
            client: client,
            auth: _auth(permissions: {PermissionKeys.patientsView}),
            initialLocation: AppRoutes.shiftDetail(_shiftActiveId),
          ),
        );

        expect(find.byKey(const Key('shift_detail_read_only_banner')), findsOneWidget);
        expect(find.textContaining('do not have permission to edit'), findsOneWidget);
      });
    });

    testWidgets('scenario 6: branch list denial shows calendar error state', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)
          ..listShiftsDenied = true
          ..listShiftsErrorMessage = 'permission_denied';

        await _pumpHost(tester, _host(client: client));

        expect(find.byKey(const Key('shift_calendar_error')), findsOneWidget);
        expect(find.text('You do not have permission to manage shifts.'), findsOneWidget);
      });
    });

    testWidgets('scenario 7a: empty period shows create guidance for managers', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)..listShiftsPayload = const [];
        await _pumpHost(tester, _host(client: client));
        expect(find.byKey(const Key('shift_calendar_empty')), findsOneWidget);
        expect(find.textContaining('Create the first shift'), findsOneWidget);
      });
    });

    testWidgets('scenario 7b: empty period shows informational copy for read-only users', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId)..listShiftsPayload = const [];
        await _pumpHost(
          tester,
          _host(
            client: client,
            auth: _auth(permissions: {PermissionKeys.patientsView}),
          ),
        );
        expect(find.byKey(const Key('shift_calendar_empty')), findsOneWidget);
        expect(find.text('No shifts are scheduled for this period.'), findsOneWidget);
        expect(find.textContaining('Create the first shift'), findsNothing);
      });
    });
  });
}
