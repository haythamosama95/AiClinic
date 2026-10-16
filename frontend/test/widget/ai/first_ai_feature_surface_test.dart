import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
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
  Future<SseConnection> submit({required CapabilityInvokeInput input, required SubmitRequestHeaders headers}) async =>
      connection;
}

Future<void> _pumpOpenStreamReady(WidgetTester tester, AiSurfaceHarness harness) async {
  await harness.pumpWidgetWithTheme(tester, Scaffold(body: harness.surface()));
  await harness.pumpUntilSurfaceReady(tester);
}

Future<void> _emitChunk(WidgetTester tester, DelayedFakeSseConnection connection, SseEvent chunk) async {
  connection.emitContent(chunk);
  await tester.idle();
  await tester.pump();
}

void main() {
  group('first AI feature surface', () {
    testWidgets('surface_provisional_content_visually_distinct', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-vis'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Draft prose in flight', 'provisional': true}),
      );

      expect(find.byKey(kAiProvisionalProseKey), findsOneWidget);

      final container = tester.widget<Container>(find.byKey(kAiProvisionalProseKey));
      final context = tester.element(find.byKey(kAiProvisionalProseKey));
      final colors = Theme.of(context).extension<AppSemanticColors>()!;
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, colors.surfaceAi);
      expect(decoration.border?.top.color, colors.borderAi);
    });

    testWidgets('surface_no_commit_control_before_completed', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-1'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Still streaming'}),
      );

      expect(find.byKey(kAiAcceptKey), findsNothing);
      expect(find.byKey(kAiDiscardKey), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('surface_accept_after_completed_behaves', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(provisionalText: 'draft', terminalText: 'Validated terminal answer'),
          ),
        ],
      );
      addTearDown(harness.disposeResolvers);

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
          SubmitOpenStreamStep(streamingThenCompleted(provisionalText: 'draft', terminalText: 'Discard me')),
        ],
      );
      addTearDown(harness.disposeResolvers);

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
          SubmitOpenStreamStep(failedStream(code: TaxonomyCode.validationFailed, requestReference: 'req-fail-1')),
        ],
      );
      addTearDown(harness.disposeResolvers);

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(kAiRequestReferenceKey), findsOneWidget);
      expect(find.textContaining('req-fail-1'), findsOneWidget);
    });

    testWidgets('surface_provisional_does_not_survive_rebuild', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-rebuild'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Ephemeral draft'}),
      );
      expect(find.text('Ephemeral draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      connection.close();

      final freshHarness = AiSurfaceHarness();
      addTearDown(freshHarness.disposeResolvers);
      await freshHarness.pumpWidgetWithTheme(tester, Scaffold(body: freshHarness.surface(autoInvoke: false)));
      await tester.pump();

      expect(find.text('Ephemeral draft'), findsNothing);
    });

    testWidgets('surface_provisional_does_not_survive_restart', (tester) async {
      final openConnection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-restart'));
      addTearDown(openConnection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(openConnection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        openConnection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Restart draft'}),
      );
      expect(find.text('Restart draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: FakeSubmitPort(
          script: [SubmitOpenStreamStep(completedStream(result: terminalProseResult('Fresh session')))],
        ),
      );
      await harness.pumpWidgetWithTheme(tester, Scaffold(body: harness.surface()));
      await tester.pumpAndSettle();

      expect(find.text('Restart draft'), findsNothing);
    });

    testWidgets('surface_uses_terminal_payload_not_chunk_assembly', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep([
            const AcceptedEvent(requestReference: 'req-term'),
            const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'WRONG assembled chunk text'}),
            CompletedEvent(result: terminalProseResult('Authoritative terminal payload')),
          ]),
        ],
      );
      addTearDown(harness.disposeResolvers);

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.text('Authoritative terminal payload'), findsOneWidget);
      expect(find.text('WRONG assembled chunk text'), findsNothing);
    });

    testWidgets('surface_accumulates_multi_delta_provisional_text', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-accum'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Hello ', 'provisional': true}),
      );
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'world', 'provisional': true}),
      );

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('Hello '), findsNothing);
      expect(find.text('world'), findsNothing);
    });

    testWidgets('surface_stream_drop_without_terminal_shows_failure', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-drop'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'orphan draft', 'provisional': true}),
      );
      expect(find.text('orphan draft'), findsOneWidget);

      connection.close();
      await tester.idle();
      await tester.pumpAndSettle();

      expect(find.text('orphan draft'), findsNothing);
      expect(find.textContaining('req-drop'), findsOneWidget);
    });

    testWidgets('surface_cancelled_returns_to_idle', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-cancel'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'going away', 'provisional': true}),
      );
      expect(find.text('going away'), findsOneWidget);

      connection.emitContent(const CancelledEvent());
      await tester.idle();
      await tester.pumpAndSettle();

      expect(find.text('going away'), findsNothing);
      expect(find.byKey(kAiIdleKey), findsOneWidget);
      expect(find.byKey(kAiRequestReferenceKey), findsNothing);
    });

    testWidgets('surface_failure_without_request_reference_shows_local_message', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep([
            const FailedEvent(code: TaxonomyCode.internalError),
          ]),
        ],
      );
      addTearDown(harness.disposeResolvers);

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(kAiRequestReferenceKey), findsNothing);
      expect(find.byKey(kAiLocalFailureKey), findsOneWidget);
    });

    testWidgets('surface_internal_error_shows_request_reference', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(failedStream(code: TaxonomyCode.internalError, requestReference: 'req-internal')),
        ],
      );
      addTearDown(harness.disposeResolvers);

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('req-internal'), findsOneWidget);
    });

    testWidgets('surface_context_invalid_shows_request_reference', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(failedStream(code: TaxonomyCode.contextInvalid, requestReference: 'req-ctx-invalid')),
        ],
      );
      addTearDown(harness.disposeResolvers);

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('req-ctx-invalid'), findsOneWidget);
    });

    testWidgets('surface_provisional_never_exported', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-export'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Never export this'}),
      );

      expect(harness.exportProbe.provisionalVisibles, isNotEmpty);
      expect(harness.exportProbe.exports, isEmpty);
    });

    testWidgets('surface_provisional_never_persisted', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-persist'));
      addTearDown(connection.close);
      final harness = AiSurfaceHarness();
      addTearDown(harness.disposeResolvers);
      harness.sdk = AiClientSdk(
        mintPort: harness.mintPort,
        submitPort: _HarnessFixedConnectionSubmitPort(connection),
      );

      await _pumpOpenStreamReady(tester, harness);
      await _emitChunk(
        tester,
        connection,
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Never persist this'}),
      );

      expect(harness.persistenceProbe.provisionalVisibles, isNotEmpty);
      expect(harness.persistenceProbe.writes, isEmpty);
    });
  });

  test('surface_contains_no_prompt_provider_or_model_identifiers', () async {
    await runArchitectureGuardOnFeaturesAi();
  });
}
