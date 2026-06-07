import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_calendar_mode.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  late ShiftRpcTestClient client;
  late ProviderContainer container;

  setUp(() async {
    AppLog.debugClearRecords();
    client = ShiftRpcTestClient(branchId: _branchId);

    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuth(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(activeBranchId: _branchId, branchIds: [_branchId]),
            ),
          ),
        ),
        shiftRepositoryProvider.overrideWith((ref) => ShiftRepository(client)),
      ],
    );
    await container.read(shiftCalendarProvider.notifier).refresh();
  });

  tearDown(() {
    container.dispose();
  });

  test('refresh surfaces permission_denied via shift RPC message mapping', () async {
    client.listShiftsDenied = true;
    client.listShiftsErrorMessage = 'permission_denied';

    await container.read(shiftCalendarProvider.notifier).refresh();

    final state = container.read(shiftCalendarProvider);
    expect(state.loading, isFalse);
    expect(state.items, isEmpty);
    expect(state.error, 'You do not have permission to manage shifts.');
    expect(AppLog.debugRecords.any((record) => record.message.contains('permission_denied')), isTrue);
  });

  test('refresh surfaces RPC_NOT_APPLIED install message', () async {
    client.rpcException = PostgrestException(
      message: 'Could not find the function public.list_shifts',
      code: 'PGRST202',
    );

    await container.read(shiftCalendarProvider.notifier).refresh();

    final state = container.read(shiftCalendarProvider);
    expect(state.error, contains('Shift management is not installed'));
  });

  test('setBranchFilter is a no-op when normalized branch id is unchanged (#13)', () async {
    client.listShiftsPayload = [
      {
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'branch_id': _branchId,
        'shift_date': '2026-06-10',
        'start_time': '09:00',
        'end_time': '17:00',
        'status': 'active',
        'is_unassigned': false,
        'assignee_names': ['Dr Shift'],
        'assignee_count': 1,
      },
    ];

    await container.read(shiftCalendarProvider.notifier).refresh();
    final callsAfterInitialRefresh = client.rpcLog.where((name) => name == 'list_shifts').length;

    await container.read(shiftCalendarProvider.notifier).setBranchFilter('  $_branchId  ');

    expect(client.rpcLog.where((name) => name == 'list_shifts').length, callsAfterInitialRefresh);
    expect(container.read(shiftCalendarProvider).loading, isFalse);
  });

  test('stale refresh responses are discarded (#13)', () async {
    final slowCompleter = Completer<dynamic>();
    final fastCompleter = Completer<dynamic>();
    client.listShiftsDelayedResponses = [slowCompleter.future, fastCompleter.future];

    final notifier = container.read(shiftCalendarProvider.notifier);
    final firstRefresh = notifier.refresh();
    final secondRefresh = notifier.setFocusDate(DateTime(2026, 6, 17));
    fastCompleter.complete(const []);
    await secondRefresh;
    slowCompleter.complete(const []);
    await firstRefresh;

    final state = container.read(shiftCalendarProvider);
    expect(state.loading, isFalse);
    expect(client.paramsFor('list_shifts')?['p_date_from'], '2026-06-15');
  });

  group('boundsFor (#12 locale week start)', () {
    test('week bounds start on Sunday when firstDayOfWeekIndex is 0', () {
      final focus = DateTime(2026, 6, 10);
      final (start, end) = ShiftCalendarController.boundsFor(focus, ShiftCalendarMode.week, firstDayOfWeekIndex: 0);

      expect(start.weekday, DateTime.sunday);
      expect(end.difference(start).inDays, 6);
      expect(start.isBefore(focus) || start == focus, isTrue);
      expect(end.isAfter(focus) || end == focus, isTrue);
    });

    test('week bounds start on Monday by default', () {
      final focus = DateTime(2026, 6, 10);
      final (start, _) = ShiftCalendarController.boundsFor(focus, ShiftCalendarMode.week);

      expect(start.weekday, DateTime.monday);
    });
  });
}
