import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:ai_clinic/features/ai/surface/provisional_prose_view.dart';
import 'package:ai_clinic/features/ai/surface/request_reference_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

class _HarnessFixedConnectionSubmitPort implements HttpsSubmitPort {
  _HarnessFixedConnectionSubmitPort(this.connection);

  final SseConnection connection;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async =>
      connection;
}

void main() {
  group('first AI feature surface', () {
    testWidgets('surface_provisional_content_visually_distinct', (tester) async {
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-vis'),
      );
      addTearDown(connection.close);
      final submitPort = _HarnessFixedConnectionSubmitPort(connection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: submitPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      connection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Draft prose in flight'},
        ),
      );
      await tester.pump();

      expect(find.byKey(kAiProvisionalProseKey), findsOneWidget);

      final container = tester.widget<Container>(find.byKey(kAiProvisionalProseKey));
      final context = tester.element(find.byKey(kAiProvisionalProseKey));
      final colors = Theme.of(context).extension<AppSemanticColors>()!;
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, colors.surfaceAi);
      expect(decoration.border?.top.color, colors.borderAi);
    });

    testWidgets('surface_no_commit_control_before_completed', (tester) async {
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-1'),
      );
      addTearDown(connection.close);
      final submitPort = _HarnessFixedConnectionSubmitPort(connection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: submitPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      connection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Still streaming'},
        ),
      );
      await tester.pump();

      expect(find.byKey(kAiAcceptKey), findsNothing);
      expect(find.byKey(kAiDiscardKey), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('surface_accept_after_completed_behaves', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(
              provisionalText: 'draft',
              terminalText: 'Validated terminal answer',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.text('Validated terminal answer'), findsOneWidget);
      await tester.tap(find.byKey(kAiAcceptKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kAiAcknowledgedKey), findsOneWidget);
      expect(harness.persistenceProbe.writes, isEmpty);
    });

    testWidgets('surface_discard_behaves', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(
              provisionalText: 'draft',
              terminalText: 'Discard me',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kAiDiscardKey));
      await tester.pumpAndSettle();

      expect(find.text('Discard me'), findsNothing);
      expect(harness.persistenceProbe.writes, isEmpty);
    });

    testWidgets('surface_failure_displays_request_reference', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(
              code: TaxonomyCode.validationFailed,
              requestReference: 'req-fail-1',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(kAiRequestReferenceKey), findsOneWidget);
      expect(find.textContaining('req-fail-1'), findsOneWidget);
    });

    testWidgets('surface_provisional_does_not_survive_rebuild', (tester) async {
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-rebuild'),
      );
      addTearDown(connection.close);
      final submitPort = _HarnessFixedConnectionSubmitPort(connection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: submitPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      connection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Ephemeral draft'},
        ),
      );
      await tester.pump();
      expect(find.text('Ephemeral draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      connection.close();

      final freshHarness = AiSurfaceHarness();
      await freshHarness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: freshHarness.surface(autoInvoke: false)),
      );
      await tester.pump();

      expect(find.text('Ephemeral draft'), findsNothing);
    });

    testWidgets('surface_provisional_does_not_survive_restart', (tester) async {
      final openConnection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-restart'),
      );
      addTearDown(openConnection.close);
      final openPort = _HarnessFixedConnectionSubmitPort(openConnection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: openPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      openConnection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Restart draft'},
        ),
      );
      await tester.pump();
      expect(find.text('Restart draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: FakeSubmitPort(
          script: [
            SubmitOpenStreamStep(
              completedStream(result: terminalProseResult('Fresh session')),
            ),
          ],
        ),
      );
      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restart draft'), findsNothing);
    });

    testWidgets('surface_uses_terminal_payload_not_chunk_assembly', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            [
              const AcceptedEvent(requestReference: 'req-term'),
              const ContentChunkEvent(
                kind: 'text_delta',
                payload: {'text': 'WRONG assembled chunk text'},
              ),
              CompletedEvent(
                result: terminalProseResult('Authoritative terminal payload'),
              ),
            ],
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.text('Authoritative terminal payload'), findsOneWidget);
      expect(find.text('WRONG assembled chunk text'), findsNothing);
    });

    testWidgets('surface_internal_error_shows_request_reference', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(
              code: TaxonomyCode.internalError,
              requestReference: 'req-internal',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('req-internal'), findsOneWidget);
    });

    testWidgets('surface_context_invalid_shows_request_reference', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(
              code: TaxonomyCode.contextInvalid,
              requestReference: 'req-ctx-invalid',
            ),
          ),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('req-ctx-invalid'), findsOneWidget);
    });

    testWidgets('surface_provisional_never_exported', (tester) async {
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-export'),
      );
      addTearDown(connection.close);
      final submitPort = _HarnessFixedConnectionSubmitPort(connection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: submitPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      connection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Never export this'},
        ),
      );
      await tester.pump();

      expect(harness.exportProbe.exports, isEmpty);
    });

    testWidgets('surface_provisional_never_persisted', (tester) async {
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-persist'),
      );
      addTearDown(connection.close);
      final submitPort = _HarnessFixedConnectionSubmitPort(connection);
      final harness = AiSurfaceHarness();
      harness.sdk = AiClientSdk(mintPort: harness.mintPort, submitPort: submitPort);

      await harness.pumpWidgetWithTheme(
        tester,
        Scaffold(body: harness.surface()),
      );
      await tester.pump();
      connection.emitContent(
        const ContentChunkEvent(
          kind: 'text_delta',
          payload: {'text': 'Never persist this'},
        ),
      );
      await tester.pump();

      expect(harness.persistenceProbe.writes, isEmpty);
    });
  });

  test('surface_contains_no_prompt_provider_or_model_identifiers', () async {
    await runArchitectureGuardOnFeaturesAi();
  });
}
