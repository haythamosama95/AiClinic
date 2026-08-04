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
    final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

    final session = await sdk.invoke(sampleInvokeInput());
    final terminal = await session.terminal;

    expect(terminal, isA<CompletedTerminal>());
    expect(mint.mintCallCount, 2);
    expect(submit.submitCallCount, 2);
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
    );

    await sdk.invoke(sampleInvokeInput());

    expect(submit.idempotencyKeys, ['stable-key-123', 'stable-key-123', 'stable-key-123']);
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
    session.cancel();

    final terminal = await session.terminal;
    expect(terminal, isA<CancelledTerminal>());
    expect(connection.closeCallCount, 1);
    expect(submit.cancelEndpointCalled, isFalse);
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

  test('sdk_unknown_error_code_treated_as_internal_error', () async {
    expect(classifyTaxonomyCode('not_in_taxonomy'), TaxonomyCode.internalError);

    final mint = FakeMintPort();
    final submit = FakeSubmitPort(
      script: [
        SubmitOpenStreamStep(
          [
            const AcceptedEvent(requestReference: 'req-unknown'),
            FailedEvent(
              code: classifyTaxonomyCode('totally_unknown_code'),
              requestReference: 'req-unknown',
            ),
          ],
        ),
      ],
    );
    final sdk = AiClientSdk(mintPort: mint, submitPort: submit);

    final session = await sdk.invoke(sampleInvokeInput());
    final terminal = await session.terminal;

    expect(terminal, isA<FailedTerminal>());
    expect((terminal as FailedTerminal).code, TaxonomyCode.internalError);
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
    );

    final session = await sdk.invoke(sampleInvokeInput());
    await session.terminal;

    expect(submit.submitCallCount, 2);
    expect(submit.idempotencyKeys, ['transport-retry-key', 'transport-retry-key']);
  });

  test('sdk_does_not_interpret_model_output', () async {
    final mint = FakeMintPort();
    const chunk = ContentChunkEvent(
      kind: 'partial_structured',
      payload: {'field': 'value', 'nested': {'a': 1}},
    );
    const terminalResult = {'raw': 'payload', 'list': [1, 2]};
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
    final terminal = await session.terminal;

    expect(terminal, isA<CompletedTerminal>());
    expect((terminal as CompletedTerminal).result, terminalResult);
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
  bool cancelEndpointCalled = false;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    return connection;
  }

  void callCancelEndpoint() {
    cancelEndpointCalled = true;
  }
}
