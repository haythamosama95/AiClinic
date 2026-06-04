import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentCalendarController branch sync', () {
    late AppointmentRpcTestClient client;

    const branchA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const branchB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

    ProviderContainer container({required _MutableAuth auth}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
    }

    setUp(() {
      client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );
    });

    test('regression: reacts when active branch is set after initial null', () async {
      final auth = _MutableAuth(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: const AuthSessionContext(
            staffProfile: StaffProfile(
              staffMemberId: 'staff',
              fullName: 'Staff',
              role: StaffRole.receptionist,
              isBootstrapAdmin: false,
              isActive: true,
            ),
            organizationId: 'org',
            branchIds: [branchA, branchB],
            activeBranchId: null,
            permissions: {},
            setupRequired: false,
          ),
        ),
      );
      final ref = container(auth: auth);
      addTearDown(ref.dispose);

      ref.read(appointmentCalendarProvider);
      await _pumpAsync();

      expect(ref.read(appointmentCalendarProvider).error, contains('active branch'));
      expect(client.lastFunction, isNull);

      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(activeBranchId: branchB, branchIds: [branchA, branchB]),
        ),
      );
      await _pumpAsync();

      expect(ref.read(appointmentCalendarProvider).selectedBranchId, branchB);
      expect(client.lastParams?['p_branch_id'], branchB);
    });

    test('regression: switches calendar data when shell changes active branch', () async {
      final auth = _MutableAuth(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(activeBranchId: branchA, branchIds: [branchA, branchB]),
        ),
      );
      final ref = container(auth: auth);
      addTearDown(ref.dispose);

      ref.read(appointmentCalendarProvider);
      await _pumpAsync();
      expect(client.lastParams?['p_branch_id'], branchA);

      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(activeBranchId: branchB, branchIds: [branchA, branchB]),
        ),
      );
      await _pumpAsync();

      expect(ref.read(appointmentCalendarProvider).selectedBranchId, branchB);
      expect(client.lastParams?['p_branch_id'], branchB);
    });
  });
}

Future<void> _pumpAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MutableAuth extends AuthSessionNotifier {
  _MutableAuth(this._state);

  AuthSessionState _state;

  @override
  AuthSessionState build() => _state;

  void setSession(AuthSessionState next) {
    _state = next;
    state = next;
  }
}
