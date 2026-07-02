import 'dart:async';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

const _sampleCompleteVisitResult = CompleteVisitResult(
  visitId: encounterTestVisitId,
  visitStatus: 'completed',
  appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  appointmentStatus: 'completed',
);

class _MockCompleteVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _MockCompleteVisitDocumentationNotifier(this._state, {this.completeDelay = Duration.zero}) : super(encounterTestVisitId);

  final VisitDocumentationState _state;
  final Duration completeDelay;

  int completeVisitCallCount = 0;
  DateTime? lastExpectedUpdatedAt;

  @override
  Future<VisitDocumentationState> build() async => _state;

  @override
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    completeVisitCallCount++;
    lastExpectedUpdatedAt = expectedUpdatedAt;
    if (completeDelay > Duration.zero) {
      await Future<void>.delayed(completeDelay);
    }
    return _sampleCompleteVisitResult;
  }
}

void main() {
  group('INT-005 — Flutter submit dialog → completeVisit', () {
    testWidgets('confirming submit calls completeVisit and closes with result', (tester) async {
      final expectedUpdatedAt = DateTime.utc(2026, 5, 31, 10);
      final mockNotifier = _MockCompleteVisitDocumentationNotifier(
        sampleEncounterDocState(
          visit: sampleEncounterVisit().copyWith(updatedAt: expectedUpdatedAt),
        ),
      );
      CompleteVisitResult? dialogResult;

      await _openSubmitDialog(
        tester,
        mockNotifier: mockNotifier,
        expectedUpdatedAt: expectedUpdatedAt,
        onClosed: (result) => dialogResult = result,
      );

      expect(find.byKey(const Key('visit_submit_confirm_button')), findsOneWidget);
      expect(find.byKey(const Key('visit_submit_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockNotifier.completeVisitCallCount, 1);
      expect(mockNotifier.lastExpectedUpdatedAt, expectedUpdatedAt);
      expect(dialogResult, _sampleCompleteVisitResult);
      expect(find.text('Submit visit'), findsNothing);
    });

    testWidgets('cancel closes dialog without calling completeVisit', (tester) async {
      final mockNotifier = _MockCompleteVisitDocumentationNotifier(sampleEncounterDocState());
      var dialogClosed = false;

      await _openSubmitDialog(
        tester,
        mockNotifier: mockNotifier,
        onClosed: (_) => dialogClosed = true,
      );

      await tester.tap(find.byKey(const Key('visit_submit_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockNotifier.completeVisitCallCount, 0);
      expect(dialogClosed, isTrue);
      expect(find.text('Submit visit'), findsNothing);
    });
  });

  group('ABUSE-001 — Double-click Submit in dialog', () {
    testWidgets('isSubmitting guard prevents duplicate completeVisit RPC', (tester) async {
      final mockNotifier = _MockCompleteVisitDocumentationNotifier(
        sampleEncounterDocState(),
        completeDelay: const Duration(milliseconds: 500),
      );

      await _openSubmitDialog(tester, mockNotifier: mockNotifier);

      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(mockNotifier.completeVisitCallCount, lessThanOrEqualTo(1));
      expect(find.byKey(const Key('visit_submit_submitting')), findsOneWidget);

      final submitButton = tester.widget<AppButton>(find.byKey(const Key('visit_submit_confirm_button')));
      expect(submitButton.onPressed, isNull);
      expect(submitButton.isLoading, isTrue);

      final cancelButton = tester.widget<AppButton>(find.byKey(const Key('visit_submit_cancel_button')));
      expect(cancelButton.onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(mockNotifier.completeVisitCallCount, 1);
      expect(find.text('Submit visit'), findsNothing);
    });
  });
}

Future<void> _openSubmitDialog(
  WidgetTester tester, {
  required _MockCompleteVisitDocumentationNotifier mockNotifier,
  DateTime? expectedUpdatedAt,
  void Function(CompleteVisitResult? result)? onClosed,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        visitDocumentationProvider(encounterTestVisitId).overrideWith(() => mockNotifier),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: AppButton(
                key: const Key('open_visit_submit_dialog'),
                label: 'Open dialog',
                onPressed: () async {
                  final result = await VisitSubmitDialog.show(
                    context,
                    visitId: encounterTestVisitId,
                    expectedUpdatedAt: expectedUpdatedAt,
                  );
                  onClosed?.call(result);
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('open_visit_submit_dialog')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
