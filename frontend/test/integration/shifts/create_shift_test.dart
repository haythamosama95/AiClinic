// US1 acceptance scenarios 1, 2, 3, 4, 5, 7, 8, 9 (UI orchestration with fake RPC).
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_create_page.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_detail_page.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/shift_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

const _branchId = '44444444-4444-4444-8444-444444444444';
const _staffId = '22222222-2222-4222-8222-222222222222';

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
        initialLocation: AppRoutes.shiftsNew,
        routes: [
          GoRoute(path: AppRoutes.shiftsNew, builder: (_, _) => const ShiftCreatePage()),
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
  group('Create shift US1 integration', () {
    testWidgets('scenario 1: create shift with staff calls RPC and navigates to detail', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await fillMinimalShiftCreateForm(tester);
        await tester.tap(find.byKey(Key('shift_staff_option_$_staffId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift_create_submit')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('create_shift'));
        expect(client.lastParams?['p_branch_id'], _branchId);
        expect(client.lastParams?['p_staff_ids'], [_staffId]);
        expect(find.textContaining('Shift detail for'), findsOneWidget);
      });
    });

    testWidgets('scenario 2: overlap conflict shows banner with staff and times', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..rpcException = const PostgrestException(
            message:
                'shift_overlap: [{"staff_member_id":"$_staffId","display_name":"Dr Shift","conflicting_shift_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","start_time":"09:00","end_time":"17:00"}]',
            code: 'P0001',
          );

        await _pumpHost(tester, _host(client: client));
        await fillMinimalShiftCreateForm(tester);
        await tester.tap(find.byKey(Key('shift_staff_option_$_staffId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift_create_submit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shift_conflict_banner')), findsOneWidget);
        expect(find.textContaining('Dr Shift is already scheduled 09:00–17:00'), findsOneWidget);
      });
    });

    testWidgets('scenario 3: ineligible staff shows eligibility message', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId)
          ..rpcException = const PostgrestException(message: 'staff_not_eligible', code: 'P0001');

        await _pumpHost(tester, _host(client: client));
        await fillMinimalShiftCreateForm(tester);
        await tester.tap(find.byKey(Key('shift_staff_option_$_staffId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift_create_submit')));
        await tester.pumpAndSettle();

        expect(find.text('A selected staff member is inactive or not assigned to this branch.'), findsOneWidget);
      });
    });

    testWidgets('scenario 4: end before start blocks submit', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        await _pumpHost(tester, _host());

        await pickShiftDateInForm(tester);
        await pickShiftStartTimeInForm(tester, startTime: const TimeOfDay(hour: 17, minute: 0));
        await pickShiftEndTimeInForm(tester, endTime: const TimeOfDay(hour: 9, minute: 0));

        expect(find.text('End time must be after start time.'), findsOneWidget);
        expect(find.byKey(const Key('shift_create_submit')), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byKey(const Key('shift_create_submit')));
        expect(button.onPressed, isNull);
      });
    });

    testWidgets('scenario 5: user without shifts.manage sees permission denied', (tester) async {
      await _pumpHost(tester, _host(auth: _auth(permissions: {PermissionKeys.patientsView})));

      expect(find.text('You do not have permission to create shifts.'), findsOneWidget);
    });

    testWidgets('scenario 7: adjacent shift times submit successfully', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await pickShiftDateInForm(tester);
        await pickShiftStartTimeInForm(tester, startTime: const TimeOfDay(hour: 17, minute: 0));
        await pickShiftEndTimeInForm(tester, endTime: const TimeOfDay(hour: 21, minute: 0));
        await tester.tap(find.byKey(Key('shift_staff_option_$_staffId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('shift_create_submit')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('create_shift'));
        expect(client.lastParams?['p_start_time'], '17:00');
        expect(client.lastParams?['p_end_time'], '21:00');
      });
    });

    testWidgets('scenario 8: date picker minimum is today in org-local calendar', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 10, 10)), () async {
        await _pumpHost(tester, _host());

        await tester.tap(find.byKey(const Key('shift_date_field')));
        await tester.pumpAndSettle();

        final picker = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
        expect(picker.firstDate, DateTime(2026, 6, 10));
      });
    });

    testWidgets('scenario 9: times outside branch working hours still submit', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 1, 10)), () async {
        final client = ShiftRpcTestClient(branchId: _branchId, staffId: _staffId);
        await _pumpHost(tester, _host(client: client));

        await pickShiftDateInForm(tester);
        await pickShiftStartTimeInForm(tester, startTime: const TimeOfDay(hour: 19, minute: 0));
        await pickShiftEndTimeInForm(tester, endTime: const TimeOfDay(hour: 22, minute: 0));

        await tester.tap(find.byKey(const Key('shift_create_submit')));
        await tester.pumpAndSettle();

        expect(client.rpcLog, contains('create_shift'));
        expect(client.lastParams?['p_start_time'], '19:00');
        expect(client.lastParams?['p_end_time'], '22:00');
      });
    });
  });
}
