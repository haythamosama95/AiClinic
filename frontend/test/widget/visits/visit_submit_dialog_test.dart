import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';

import '../../support/visit_rpc_test_client.dart';

const _visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

void main() {
  group('VisitSubmitDialog', () {
    testWidgets('trivial: shows confirm and cancel actions', (tester) async {
      await _pumpDialog(tester);

      expect(find.byKey(const Key('visit_submit_dialog')), findsOneWidget);
      expect(find.byKey(const Key('visit_submit_confirm_button')), findsOneWidget);
      expect(find.byKey(const Key('visit_submit_cancel_button')), findsOneWidget);
    });

    testWidgets('advanced: successful submit calls complete_visit and closes', (tester) async {
      final client = VisitRpcTestClient();
      CompleteVisitResult? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await VisitSubmitDialog.show(context, visitId: _visitId);
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('complete_visit'));
      expect(result, isNotNull);
      expect(result!.visitStatus, 'completed');
      expect(find.byKey(const Key('visit_submit_dialog')), findsNothing);
    });

    testWidgets('invalid state: SOAP_REQUIRED_FOR_COMPLETE shows error and stays open', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'complete_visit': {
            'success': false,
            'error_code': 'SOAP_REQUIRED_FOR_COMPLETE',
            'error_message': 'SOAP required',
          },
        },
      );

      await _pumpDialog(tester, client: client);
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_submit_error_label')), findsOneWidget);
      expect(find.textContaining('before submitting the visit'), findsOneWidget);
      expect(find.byKey(const Key('visit_submit_dialog')), findsOneWidget);
    });

    testWidgets('stupid usage: cancel closes without RPC', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpDialog(tester, client: client);
      await tester.tap(find.byKey(const Key('visit_submit_cancel_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, isEmpty);
      expect(find.byKey(const Key('visit_submit_dialog')), findsNothing);
    });

    testWidgets('edge case: FORBIDDEN shows error message', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'complete_visit': {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Denied'},
        },
      );

      await _pumpDialog(tester, client: client);
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_submit_error_label')), findsOneWidget);
      expect(find.textContaining('permission'), findsOneWidget);
    });

    testWidgets('regression: STALE_SOAP surfaces reload message', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'complete_visit': {'success': false, 'error_code': 'STALE_SOAP', 'error_message': 'Stale'},
        },
      );

      await _pumpDialog(tester, client: client);
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('updated elsewhere'), findsOneWidget);
    });
  });
}

Future<void> _pumpDialog(WidgetTester tester, {VisitRpcTestClient? client}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client ?? VisitRpcTestClient()))],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => VisitSubmitDialog.show(context, visitId: _visitId),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
