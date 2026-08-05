import 'dart:async';
import 'dart:io';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('AI Client SDK', () {
    test('sdk_aat_acquired_and_cached', () async {
      final mint = FakeMintPort(tokens: ['token-a']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(completedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-2')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final first = await sdk.invoke(sampleInvokeInput());
      await first.terminal;
      final second = await sdk.invoke(sampleInvokeInput());
      await second.terminal;

      expect(mint.mintCallCount, 1);
      expect(submit.submitCallCount, 2);
      expect(submit.headerLog.every((h) => h.aat == 'token-a'), isTrue);
    });

    test('sdk_unauthenticated_remints_once_then_succeeds', () async {
      final mint = FakeMintPort(tokens: ['stale-token', 'fresh-token']);
      final submit = FakeSubmitPort(
        script: [
          SubmitHttpErrorStep(code: TaxonomyCode.unauthenticated),
          SubmitOpenStreamStep(completedStream()),
        ],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'remint-stable-key',
      );

      final session = await sdk.invoke(sampleInvokeInput());
      final terminal = await session.terminal;

      expect(terminal, isA<CompletedTerminal>());
      expect(mint.mintCallCount, 2);
      expect(submit.submitCallCount, 2);
      expect(submit.idempotencyKeys, ['remint-stable-key', 'remint-stable-key']);
      expect(submit.headerLog[0].aat, 'stale-token');
      expect(submit.headerLog[1].aat, 'fresh-token');
    });

    test('sdk_unauthenticated_no_remint_loop', () async {
      final mint = FakeMintPort(tokens: ['stale-1', 'stale-2', 'stale-3']);
      final submit = FakeSubmitPort(
        script: [
          SubmitHttpErrorStep(code: TaxonomyCode.unauthenticated),
          SubmitHttpErrorStep(code: TaxonomyCode.unauthenticated),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      await expectLater(
        sdk.invoke(sampleInvokeInput()),
        throwsA(
          isA<PlatformHttpException>().having(
            (e) => e.code,
            'code',
            TaxonomyCode.unauthenticated,
          ),
        ),
      );
      expect(mint.mintCallCount, 2);
      expect(submit.submitCallCount, 2);
    });

    test('sdk_idempotency_key_stable_across_transport_retries', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitOpenStreamStep(completedStream()),
        ],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'stable-key-123',
        transportBackoff: (_) => Duration.zero,
      );

      await sdk.invoke(sampleInvokeInput());

      expect(
        submit.idempotencyKeys,
        ['stable-key-123', 'stable-key-123', 'stable-key-123'],
      );
    });

    test('sdk_stream_consumed_to_terminal_event', () async {
      final mint = FakeMintPort();
      final resultPayload = {'validated': true, 'note': 'draft'};
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            completedStream(result: resultPayload, requestReference: 'req-term'),
          ),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      final terminal = await session.terminal;

      expect(terminal, isA<CompletedTerminal>());
      expect((terminal as CompletedTerminal).result, resultPayload);
      expect(sdk.lastRequestReference, 'req-term');
    });

    test('sdk_cancel_closes_stream', () async {
      final mint = FakeMintPort();
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-cancel'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      final relayed = <SseEvent>[];
      final sub = session.events.listen(relayed.add);
      // Allow accepted to arrive before cancel.
      await Future<void>.delayed(Duration.zero);
      session.cancel();

      final terminal = await session.terminal;
      await sub.cancel();

      expect(terminal, isA<CancelledTerminal>());
      expect(connection.closeCallCount, 1);
      expect(relayed.whereType<CancelledEvent>(), isEmpty);
      expect(
        submit.runtimeType.toString(),
        isNot(contains('CancelEndpoint')),
        reason: 'cancel is connection.close only — no separate cancel endpoint',
      );
    });

    test('sdk_cancel_synthesizes_cancelled_without_wire_event', () async {
      final mint = FakeMintPort();
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-synth-cancel'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      await Future<void>.delayed(Duration.zero);
      session.cancel();
      final terminal = await session.terminal;

      expect(terminal, isA<CancelledTerminal>());
      expect(connection.closeCallCount, 1);
    });

    for (final code in terminalNoRetryCodes) {
      final wire = taxonomyCodeToWire(code);
      test('sdk_no_retry_after_$wire', () async {
        final mint = FakeMintPort();
        final submit = FakeSubmitPort(
          script: [SubmitOpenStreamStep(failedStream(code: code))],
        );
        final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

        final session = await sdk.invoke(sampleInvokeInput());
        final terminal = await session.terminal;

        expect(terminal, isA<FailedTerminal>());
        expect((terminal as FailedTerminal).code, code);
        expect(submit.submitCallCount, 1);
      });
    }

    for (final code in terminalNoRetryCodes) {
      final wire = taxonomyCodeToWire(code);
      test('sdk_http_no_retry_after_$wire', () async {
        final mint = FakeMintPort();
        final submit = FakeSubmitPort(
          script: [SubmitHttpErrorStep(code: code)],
        );
        final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

        await expectLater(
          sdk.invoke(sampleInvokeInput()),
          throwsA(
            isA<PlatformHttpException>().having((e) => e.code, 'code', code),
          ),
        );
        expect(submit.submitCallCount, 1);
        expect(mint.mintCallCount, 1);
      });
    }

    test('sdk_last_request_reference_retained', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            completedStream(requestReference: 'req-support-42'),
          ),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      await session.terminal;

      expect(sdk.lastRequestReference, 'req-support-42');
    });

    test('sdk_last_request_reference_retained_from_http_error_body', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitHttpErrorStep(
            code: TaxonomyCode.quotaExhausted,
            requestReference: 'req-http-99',
          ),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      await expectLater(
        sdk.invoke(sampleInvokeInput()),
        throwsA(isA<PlatformHttpException>()),
      );
      expect(sdk.lastRequestReference, 'req-http-99');
    });

    test('sdk_unknown_error_code_treated_as_internal_error', () async {
      expect(classifyTaxonomyCode('not_in_taxonomy'), TaxonomyCode.internalError);

      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep([
            const AcceptedEvent(requestReference: 'req-unknown'),
            FailedEvent.fromWire(
              'totally_unknown_code',
              requestReference: 'req-unknown',
            ),
          ]),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      final terminal = await session.terminal;

      expect(terminal, isA<FailedTerminal>());
      expect((terminal as FailedTerminal).code, TaxonomyCode.internalError);
    });

    test('failed_event_from_wire_maps_unknown_to_internal_error', () {
      final event = FailedEvent.fromWire('totally_unknown_code');
      expect(event.code, TaxonomyCode.internalError);
    });

    test('failed_event_from_wire_preserves_known_code', () {
      final event = FailedEvent.fromWire('quota_exhausted');
      expect(event.code, TaxonomyCode.quotaExhausted);
    });

    test('sdk_transport_retry_allowed', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitOpenStreamStep(completedStream()),
        ],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'transport-retry-key',
        transportBackoff: (_) => Duration.zero,
      );

      final session = await sdk.invoke(sampleInvokeInput());
      await session.terminal;

      expect(submit.submitCallCount, 2);
      expect(
        submit.idempotencyKeys,
        ['transport-retry-key', 'transport-retry-key'],
      );
    });

    test('sdk_transport_retry_exhausts_after_ceiling', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
        ],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'exhaust-key',
        transportBackoff: (_) => Duration.zero,
      );

      await expectLater(
        sdk.invoke(sampleInvokeInput()),
        throwsA(
          isA<TransportRetryExhausted>()
              .having((e) => e.idempotencyKey, 'key', 'exhaust-key')
              .having((e) => e.attempts, 'attempts', 3),
        ),
      );
      expect(submit.submitCallCount, 3);
      expect(submit.idempotencyKeys, ['exhaust-key', 'exhaust-key', 'exhaust-key']);
    });

    test('sdk_transport_retry_applies_backoff_between_attempts', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitOpenStreamStep(completedStream()),
        ],
      );
      final backoffCalls = <int>[];
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        transportBackoff: (attempt) {
          backoffCalls.add(attempt);
          return Duration.zero;
        },
      );

      await sdk.invoke(sampleInvokeInput());

      expect(backoffCalls, [1, 2]);
      expect(submit.submitCallCount, 3);
    });

    test('sdk_invoke_cancel_signal_aborts_transport_retries', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
        ],
      );
      final cancel = Completer<void>();
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        transportBackoff: (_) {
          if (!cancel.isCompleted) {
            cancel.complete();
          }
          return const Duration(hours: 1);
        },
      );

      await expectLater(
        sdk.invoke(sampleInvokeInput(), cancelSignal: cancel.future),
        throwsA(isA<InvokeCancelledException>()),
      );
      expect(submit.submitCallCount, lessThan(kDefaultMaxTransportAttempts));
    });

    test('sdk_does_not_interpret_model_output', () async {
      final mint = FakeMintPort();
      const chunk = ContentChunkEvent(
        kind: 'partial_structured',
        payload: {'field': 'value', 'nested': {'a': 1}},
      );
      const terminalResult = {
        'raw': 'payload',
        'list': [1, 2],
      };
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep([
            const AcceptedEvent(requestReference: 'req-raw'),
            chunk,
            const CompletedEvent(result: terminalResult),
          ]),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      final eventsFuture = session.events.toList();
      final terminal = await session.terminal;
      final events = await eventsFuture;

      expect(terminal, isA<CompletedTerminal>());
      expect((terminal as CompletedTerminal).result, terminalResult);
      expect(events, hasLength(3));
      expect(events[0], isA<AcceptedEvent>());
      expect(events[1], same(chunk));
      expect(events[2], isA<CompletedEvent>());
      expect((events[2] as CompletedEvent).result, terminalResult);
    });

    test('sdk_session_events_allow_caller_listen_with_single_sub_source',
        () async {
      final mint = FakeMintPort();
      final connection = FakeSseConnection(
        events: completedStream(requestReference: 'req-listen'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      final collected = <SseEvent>[];
      final sub = session.events.listen(collected.add);
      final terminal = await session.terminal;
      await sub.cancel();

      expect(terminal, isA<CompletedTerminal>());
      expect(collected.whereType<AcceptedEvent>(), isNotEmpty);
      expect(collected.whereType<CompletedEvent>(), isNotEmpty);
    });

    test('sdk_stream_end_without_terminal_is_not_completed', () async {
      final mint = FakeMintPort();
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-silence'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      await Future<void>.delayed(Duration.zero);
      connection.drop();
      final terminal = await session.terminal;

      expect(terminal, isA<StreamDroppedTerminal>());
      expect(
        (terminal as StreamDroppedTerminal).requestReference,
        'req-silence',
      );
      expect(terminal.retrySafe, isTrue);
      expect(sdk.lastRequestReference, 'req-silence');
    });

    test('sdk_stream_error_surfaces_stream_dropped_terminal', () async {
      final mint = FakeMintPort();
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-err'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final session = await sdk.invoke(sampleInvokeInput());
      await Future<void>.delayed(Duration.zero);
      connection.fail(StateError('socket reset'));
      final terminal = await session.terminal;

      expect(terminal, isA<StreamDroppedTerminal>());
      expect((terminal as StreamDroppedTerminal).cause, isA<StateError>());
      expect(terminal.requestReference, 'req-err');
    });

    test('sdk_concurrent_cold_invokes_single_flight_mint', () async {
      final mint = FakeMintPort(tokens: ['shared-token']);
      mint.gate = Completer<void>();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(completedStream(requestReference: 'req-a')),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-b')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final first = sdk.invoke(sampleInvokeInput());
      final second = sdk.invoke(sampleInvokeInput());
      await Future<void>.delayed(Duration.zero);
      expect(mint.mintCallCount, 1);
      mint.gate!.complete();

      final sessions = await Future.wait([first, second]);
      await Future.wait(sessions.map((s) => s.terminal));

      expect(mint.mintCallCount, 1);
      expect(submit.headerLog.every((h) => h.aat == 'shared-token'), isTrue);
    });

    test('sdk_concurrent_unauthenticated_single_flight_remint', () async {
      final mint = FakeMintPort(tokens: ['stale', 'fresh']);
      final submit = FakeSubmitPort(
        script: [
          SubmitHttpErrorStep(code: TaxonomyCode.unauthenticated),
          SubmitHttpErrorStep(code: TaxonomyCode.unauthenticated),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-a')),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-b')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      final sessions = await Future.wait([
        sdk.invoke(sampleInvokeInput()),
        sdk.invoke(sampleInvokeInput()),
      ]);
      await Future.wait(sessions.map((s) => s.terminal));

      // Cold mint + one shared remint (not N remints for N 401s).
      expect(mint.mintCallCount, 2);
      expect(submit.submitCallCount, 4);
    });

    test('sdk_default_idempotency_key_is_at_least_128_bit_hex', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [SubmitOpenStreamStep(completedStream())],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      await sdk.invoke(sampleInvokeInput());

      final key = submit.idempotencyKeys.single;
      expect(key.length, greaterThanOrEqualTo(32));
      expect(key, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('sdk_default_trace_id_uses_secure_length', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [SubmitOpenStreamStep(completedStream())],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

      await sdk.invoke(sampleInvokeInput());

      final traceId = submit.headerLog.single.traceId;
      expect(traceId.length, greaterThanOrEqualTo(32));
      expect(traceId, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('sdk_invoke_per_call_idempotency_key_overrides_factory', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [SubmitOpenStreamStep(completedStream())],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'factory-key',
      );

      await sdk.invoke(sampleInvokeInput(), idempotencyKey: 'call-key');

      expect(submit.idempotencyKeys, ['call-key']);
    });

    test('sdk_invoke_omitted_key_uses_factory', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [SubmitOpenStreamStep(completedStream())],
      );
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () => 'factory-key',
      );

      await sdk.invoke(sampleInvokeInput());

      expect(submit.idempotencyKeys, ['factory-key']);
    });

    test('sdk_contains_no_prompt_provider_or_model_identifiers', () async {
      final result = await Process.run(
        'dart',
        ['run', 'tool/architecture_guard/architecture_guard.dart'],
        workingDirectory: _frontendRoot(),
        runInShell: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('architecture_guard: clean'));
    });
  });
}

String _frontendRoot() {
  final dir = Directory.current;
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    return dir.path;
  }
  return '${dir.path}/frontend';
}

/// Submit port that always returns a pre-built connection (for cancel tests).
class _FixedConnectionSubmitPort implements HttpsSubmitPort {
  _FixedConnectionSubmitPort(this.connection);

  final SseConnection connection;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    return connection;
  }
}
