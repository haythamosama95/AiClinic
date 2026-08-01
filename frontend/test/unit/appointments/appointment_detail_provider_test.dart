import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
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
  group('appointmentDetailProvider', () {
    late AppointmentRpcTestClient client;

    setUp(() {
      client = AppointmentRpcTestClient();
    });

    ProviderContainer createContainer(AuthSessionState authState) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
    }

    test('invalid state: permission denied throws StateError without RPC', () async {
      final container = createContainer(
        const AuthSessionState(status: AuthSessionStatus.authenticated),
      );
      addTearDown(container.dispose);

      final future = container.read(appointmentDetailProvider('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb').future);

      await expectLater(future, throwsA(isA<StateError>()));
      expect(client.lastFunction, isNull);
    });

    test('trivial: permitted session fetches appointment detail', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {'appointments.read'}),
        ),
      );
      addTearDown(container.dispose);

      final detail = await container.read(
        appointmentDetailProvider('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb').future,
      );

      expect(detail.patientName, 'Test Patient');
      expect(detail.status, AppointmentStatus.scheduled);
      expect(client.lastFunction, 'get_appointment');
    });

    test('invalid state: RpcFailure propagates to AsyncValue error', () async {
      client.rpcResults['get_appointment'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Appointment not found',
      };

      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {'appointments.read'}),
        ),
      );
      addTearDown(container.dispose);

<<<<<<< HEAD
      final future = container.read(appointmentDetailProvider('missing').future);

      await expectLater(
        future,
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
=======
      final provider = appointmentDetailProvider('missing');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND'),
>>>>>>> master
      );
    });

    test('advanced: family caches each appointment id separately', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: {'appointments.read'}),
        ),
      );
      addTearDown(container.dispose);

      client.rpcResults['get_appointment'] = {
        'success': true,
        'data': appointmentRpcDefaultDetailItem(id: 'id-a'),
      };
      final first = await container.read(appointmentDetailProvider('id-a').future);

      client.rpcResults['get_appointment'] = {
        'success': true,
        'data': appointmentRpcDefaultDetailItem(id: 'id-b', patientName: 'Other Patient'),
      };
      final second = await container.read(appointmentDetailProvider('id-b').future);

      expect(first.id, 'id-a');
      expect(second.id, 'id-b');
      expect(client.rpcCallCounts['get_appointment'], 2);
    });
  });
}
