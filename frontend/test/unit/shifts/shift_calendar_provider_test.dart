import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
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

  setUp(() {
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
}
