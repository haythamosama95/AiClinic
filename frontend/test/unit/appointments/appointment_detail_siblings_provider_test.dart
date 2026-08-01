import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_siblings_provider.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
=======
>>>>>>> master
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

void main() {
  group('appointmentDetailSiblingsProvider', () {
    late AppointmentRpcTestClient client;

    setUp(() {
      client = AppointmentRpcTestClient();
    });

    ProviderContainer createContainer({String timezone = 'Africa/Cairo'}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                ).copyWith(organizationTimezone: timezone),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
    }

    test('stupid usage: blank branch id returns empty list without RPC', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final items = await container.read(
        appointmentDetailSiblingsProvider(
<<<<<<< HEAD
          const AppointmentDetailSiblingsQuery(
=======
          AppointmentDetailSiblingsQuery(
>>>>>>> master
            branchId: '   ',
            startTime: DateTime.utc(2026, 6, 4, 10),
          ),
        ).future,
      );

      expect(items, isEmpty);
      expect(client.lastFunction, isNull);
    });

    test('advanced: uses org-timezone day bounds for list_appointments', () async {
      const branchId = '44444444-4444-4444-8444-444444444444';
      const timezone = 'Africa/Cairo';
      final startTime = DateTime.utc(2026, 6, 4, 21);
      final container = createContainer(timezone: timezone);
      addTearDown(container.dispose);

      await container.read(
        appointmentDetailSiblingsProvider(
          AppointmentDetailSiblingsQuery(branchId: branchId, startTime: startTime),
        ).future,
      );

      final day = calendarDayInOrganizationTimezone(timezone, startTime);
      final range = appointmentTodayRangeInTimezone(timezone, day.toUtc());
      expect(client.lastParams?['p_from'], range.from.toIso8601String());
      expect(client.lastParams?['p_to'], range.to.toIso8601String());
      expect(client.lastParams?['p_branch_id'], branchId);
    });

    test('invalid state: repository error propagates', () async {
      client.rpcResults['list_appointments'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      final container = createContainer();
      addTearDown(container.dispose);

<<<<<<< HEAD
      final future = container.read(
        appointmentDetailSiblingsProvider(
          const AppointmentDetailSiblingsQuery(
            branchId: '44444444-4444-4444-8444-444444444444',
            startTime: DateTime.utc(2026, 6, 4, 10),
          ),
        ).future,
      );

      await expectLater(
        future,
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
=======
      final provider = appointmentDetailSiblingsProvider(
        AppointmentDetailSiblingsQuery(
          branchId: '44444444-4444-4444-8444-444444444444',
          startTime: DateTime.utc(2026, 6, 4, 10),
        ),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN'),
>>>>>>> master
      );
    });

    test('advanced: distinct query objects are cached independently', () async {
      final container = createContainer();
      addTearDown(container.dispose);

<<<<<<< HEAD
      const queryA = AppointmentDetailSiblingsQuery(
        branchId: '44444444-4444-4444-8444-444444444444',
        startTime: DateTime.utc(2026, 6, 4, 10),
      );
      const queryB = AppointmentDetailSiblingsQuery(
=======
      final queryA = AppointmentDetailSiblingsQuery(
        branchId: '44444444-4444-4444-8444-444444444444',
        startTime: DateTime.utc(2026, 6, 4, 10),
      );
      final queryB = AppointmentDetailSiblingsQuery(
>>>>>>> master
        branchId: '44444444-4444-4444-8444-444444444444',
        startTime: DateTime.utc(2026, 6, 4, 12),
      );

      expect(queryA == queryB, isFalse);

      await container.read(appointmentDetailSiblingsProvider(queryA).future);
      await container.read(appointmentDetailSiblingsProvider(queryB).future);

      expect(client.rpcCallCounts['list_appointments'], 2);
    });
  });
}
