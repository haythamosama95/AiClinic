import 'dart:async';

import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_archive_dialog.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';
import '../../support/patient_rpc_test_client.dart';

Future<void> _pumpDialog(WidgetTester tester, PatientRpcTestClient client) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(permissions: const {'patients.view', 'patients.delete'}),
            ),
          ),
        ),
        patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => PatientArchiveDialog.show(
                    context,
                    patientId: '11111111-1111-4111-8111-111111111111',
                    patientName: 'Ahmed Hassan',
                  ),
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PatientArchiveDialog', () {
    testWidgets('trivial: shows patient name and confirm actions', (tester) async {
      await _pumpDialog(tester, PatientRpcTestClient());

      expect(find.byKey(const Key('patient_archive_dialog')), findsOneWidget);
      expect(find.textContaining('Ahmed Hassan'), findsOneWidget);
      expect(find.byKey(const Key('patient_archive_confirm')), findsOneWidget);
      expect(find.byKey(const Key('patient_archive_cancel')), findsOneWidget);
    });

    testWidgets('advanced: confirm archives and closes with true', (tester) async {
      final client = PatientRpcTestClient();
      bool? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client))],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      result = await PatientArchiveDialog.show(
                        context,
                        patientId: '11111111-1111-4111-8111-111111111111',
                        patientName: 'Ahmed Hassan',
                      );
                    },
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patient_archive_confirm')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(client.lastFunction, 'archive_patient');
    });

    testWidgets('stupid usage: cancel closes without RPC', (tester) async {
      final client = PatientRpcTestClient();

      await _pumpDialog(tester, client);
      await tester.tap(find.byKey(const Key('patient_archive_cancel')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, isNull);
    });

    testWidgets('edge case: PATIENT_ARCHIVED shows error in dialog', (tester) async {
      final client = PatientRpcTestClient()
        ..rpcResults['archive_patient'] = {
          'success': false,
          'error_code': 'PATIENT_ARCHIVED',
          'error_message': 'Already archived',
        };

      await _pumpDialog(tester, client);
      await tester.tap(find.byKey(const Key('patient_archive_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('archived'), findsWidgets);
      expect(find.byKey(const Key('patient_archive_dialog')), findsOneWidget);
    });

    testWidgets('invalid state: FORBIDDEN shows permission message', (tester) async {
      final client = PatientRpcTestClient()
        ..rpcResults['archive_patient'] = {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Forbidden'};

      await _pumpDialog(tester, client);
      await tester.tap(find.byKey(const Key('patient_archive_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission'), findsOneWidget);
    });

    testWidgets('regression: confirm button disabled while archiving', (tester) async {
      final client = _SlowArchiveClient();

      await _pumpDialog(tester, client);
      await tester.tap(find.byKey(const Key('patient_archive_confirm')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}

class _SlowArchiveClient extends PatientRpcTestClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'archive_patient') {
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      return _SlowRpc() as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _SlowRpc extends FakePostgrestRpc {
  _SlowRpc()
    : super({
        'success': true,
        'data': {'patient_id': '11111111-1111-4111-8111-111111111111'},
      });

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.delayed(const Duration(milliseconds: 300), () => result).then(onValue, onError: onError);
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
