import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentCancelDialog', () {
    testWidgets('trivial: shows patient and optional reason field', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_cancel_dialog')), findsOneWidget);
      expect(find.byKey(const Key('appointment_cancel_reason')), findsOneWidget);
      expect(find.textContaining('Jane Doe'), findsOneWidget);
    });

    testWidgets('advanced: cancel confirm calls cancel_appointment RPC', (tester) async {
      final client = AppointmentRpcTestClient();
      AppointmentStatus? popped;

      await tester.pumpWidget(_host(client: client, onClosed: (status) => popped = status));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_cancel_reason')), 'Patient called');
      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'cancel_appointment');
      expect(client.lastParams?['p_reason'], 'Patient called');
      expect(popped, AppointmentStatus.cancelled);
    });

    testWidgets('advanced: no-show calls update_appointment_status', (tester) async {
      final client = AppointmentRpcTestClient();
      AppointmentStatus? popped;

      await tester.pumpWidget(_host(client: client, onClosed: (status) => popped = status));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_no_show')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'update_appointment_status');
      expect(client.lastParams?['p_new_status'], 'no_show');
      expect(popped, AppointmentStatus.noShow);
    });

    testWidgets('invalid state: completed cancel shows inline error', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'cancel_appointment': {
            'success': false,
            'error_code': 'INVALID_INPUT',
            'error_message': 'Only scheduled or checked-in appointments can be cancelled.',
          },
        },
      );

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_cancel_error')), findsOneWidget);
      expect(find.textContaining('checked-in'), findsOneWidget);
    });

    testWidgets('stupid usage: dismiss closes without RPC', (tester) async {
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_dismiss')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, isNull);
    });

    testWidgets('edge case: empty reason omits p_reason param', (tester) async {
      final client = AppointmentRpcTestClient();

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'cancel_appointment');
      expect(client.lastParams?.containsKey('p_reason'), isFalse);
    });

    testWidgets('regression: no-show INVALID_TRANSITION shows error', (tester) async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'update_appointment_status': {
            'success': false,
            'error_code': 'INVALID_TRANSITION',
            'error_message': 'This status change is not allowed.',
          },
        },
      );

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_cancel_no_show')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_cancel_error')), findsOneWidget);
      expect(find.textContaining('not allowed'), findsOneWidget);
    });
  });
}

AppointmentListItem _item() {
  return AppointmentListItem(
    id: 'appt-1',
    patientId: 'patient-1',
    patientName: 'Jane Doe',
    doctorName: 'Dr Smith',
    startTime: DateTime.utc(2026, 6, 1, 10),
    endTime: DateTime.utc(2026, 6, 1, 10, 30),
    type: AppointmentType.planned,
    status: AppointmentStatus.scheduled,
  );
}

Widget _host({AppointmentRpcTestClient? client, void Function(AppointmentStatus? status)? onClosed}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(activeBranchId: branchId, branchIds: [branchId]),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client ?? AppointmentRpcTestClient())),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await AppointmentCancelDialog.show(context, item: _item());
                  onClosed?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
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
