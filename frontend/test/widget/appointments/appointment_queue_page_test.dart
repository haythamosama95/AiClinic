import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentQueuePage', () {
    testWidgets('trivial: shows sorted queue rows', (tester) async {
      final day = DateTime.now();
      final morning = DateTime(day.year, day.month, day.day, 9).toUtc();
      final afternoon = DateTime(day.year, day.month, day.day, 15).toUtc();

      await tester.pumpWidget(
        _host(
          rpcResults: {
            'list_appointments': {
              'success': true,
              'data': {
                'items': [_row('late', afternoon), _row('early', morning)],
              },
            },
          },
          realtimeConnection: AppointmentQueueRealtimeConnection.live,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_queue_list')), findsOneWidget);
      expect(find.byKey(const Key('appointments_queue_row_early')), findsOneWidget);
      expect(find.text('Patient early'), findsOneWidget);
      expect(find.byKey(const Key('appointments_queue_live_banner')), findsOneWidget);
    });

    testWidgets('empty state when no appointments today', (tester) async {
      await tester.pumpWidget(
        _host(
          rpcResults: {
            'list_appointments': {
              'success': true,
              'data': {'items': []},
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_queue_empty')), findsOneWidget);
    });

    testWidgets('degraded banner and manual refresh', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );

      await tester.pumpWidget(
        _host(rpcResults: const {}, client: client, realtimeConnection: AppointmentQueueRealtimeConnection.degraded),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_queue_degraded_banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointments_queue_refresh')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'list_appointments');
    });

    testWidgets('permission denied without appointment grants', (tester) async {
      await tester.pumpWidget(
        _host(
          permissions: const {},
          rpcResults: {
            'list_appointments': {
              'success': true,
              'data': {'items': []},
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to view appointments.'), findsOneWidget);
      expect(find.byKey(const Key('appointments_queue_list')), findsNothing);
    });
  });
}

Map<String, dynamic> _row(String id, DateTime start) {
  final end = start.add(const Duration(minutes: 20));
  return {
    'id': id,
    'patient_id': 'p',
    'patient_name': 'Patient $id',
    'doctor_id': 'd',
    'doctor_name': 'Dr',
    'start_time': start.toIso8601String(),
    'end_time': end.toIso8601String(),
    'type': 'planned',
    'status': 'scheduled',
  };
}

Widget _host({
  required Map<String, Map<String, dynamic>> rpcResults,
  Set<String> permissions = const {PermissionKeys.appointmentsCreate},
  AppointmentQueueRealtimeConnection realtimeConnection = AppointmentQueueRealtimeConnection.degraded,
  AppointmentRpcTestClient? client,
}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: branchId, branchIds: [branchId]),
  );

  final rpcClient = client ?? AppointmentRpcTestClient(rpcResults: rpcResults);

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpcClient)),
      appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeRealtime(realtimeConnection)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.appointmentsQueue,
        routes: [GoRoute(path: AppRoutes.appointmentsQueue, builder: (context, state) => const AppointmentQueuePage())],
      ),
    ),
  );
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _FakeRealtime implements AppointmentQueueRealtimeClient {
  _FakeRealtime(this.connection);
  final AppointmentQueueRealtimeConnection connection;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    onConnectionChanged(connection);
  }

  @override
  void unsubscribe() {}
}
