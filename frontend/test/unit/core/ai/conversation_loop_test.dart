import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ai/conversation_loop.dart';
import 'package:ai_clinic/core/ai/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Conversation loop', () {
    test('requested_keys_resolved_through_existing_resolver_no_capability_branching',
        () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-leg-2')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final store = ConversationStore(
        conversationId: 'conv-loop-001',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: resolver,
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      await loop.submitLeg('Summarise the visit.');

      expect(resolver.resolveCalls, hasLength(1));
      expect(resolver.resolveCalls.single, [visitChiefComplaintV1Key]);
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_requested'),
        isTrue,
      );
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_resolved'),
        isTrue,
      );
    });

    test('each_leg_uses_new_idempotency_key', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2', 't3']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(completedStream(requestReference: 'req-1')),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-2')),
        ],
      );
      var leg = 0;
      final keys = ['leg-key-1', 'leg-key-2'];
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-keys',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
        idempotencyKeyFactory: () => keys[leg++],
      );

      await loop.submitLeg('First question');
      await loop.submitLeg('Second question');

      expect(submit.idempotencyKeys, ['leg-key-1', 'leg-key-2']);
      expect(submit.idempotencyKeys.toSet(), hasLength(2));
    });

    test('conversation_loop_preserves_aat_cache_across_legs', () async {
      final mint = FakeMintPort(tokens: ['shared-aat']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(completedStream(requestReference: 'req-1')),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-2')),
        ],
      );
      var leg = 0;
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-aat-cache',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
        idempotencyKeyFactory: () => 'leg-${++leg}',
      );

      await loop.submitLeg('First question');
      await loop.submitLeg('Second question');

      expect(mint.mintCallCount, 1);
      expect(submit.headerLog.every((h) => h.aat == 'shared-aat'), isTrue);
    });

    test('closing_one_leg_stream_cancels_only_that_leg', () async {
      final mint = FakeMintPort();
      final connection = DelayedFakeSseConnection(
        accepted: const AcceptedEvent(requestReference: 'req-cancel-leg'),
      );
      final submit = _FixedConnectionSubmitPort(connection);
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-cancel',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      final terminal = await loop.submitLeg(
        'In-flight question',
        onSession: (_) => loop.cancelCurrentLeg(),
      );

      expect(terminal, isA<CancelledTerminal>());
      expect(connection.closeCallCount, 1);
      expect(store.transcript, isNotEmpty);
    });

    test('conversation_survives_cancelled_leg', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep([
            const AcceptedEvent(requestReference: 'req-cancel'),
            const CancelledEvent(),
          ]),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-after-cancel')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-survive',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      final first = await loop.submitLeg('Cancelled leg');
      expect(first, isA<CancelledTerminal>());
      expect(store.transcript, isNotEmpty);

      final second = await loop.submitLeg('Follow-up after cancel');
      expect(second, isA<CompletedTerminal>());
      expect(submit.submitCallCount, 2);
    });

    test('append_completed_answer_to_transcript', () async {
      final mint = FakeMintPort();
      const answer = 'Validated clinical summary.';
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            completedStream(
              requestReference: 'req-complete',
              result: {'text': answer},
            ),
          ),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-complete',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      await loop.submitLeg('Generate summary');

      expect(
        store.transcript.any(
          (turn) => turn['kind'] == 'model' && turn['text'] == answer,
        ),
        isTrue,
      );
    });

    test('append_context_request_and_resolved_payload_to_transcript', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-after-ctx')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-append',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: FakeContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      await loop.submitLeg('Need chief complaint');

      final requestedIndex = store.transcript.indexWhere(
        (turn) => turn['kind'] == 'context_requested',
      );
      final resolvedIndex = store.transcript.indexWhere(
        (turn) => turn['kind'] == 'context_resolved',
      );
      expect(requestedIndex, greaterThanOrEqualTo(0));
      expect(resolvedIndex, greaterThan(requestedIndex));
    });

    test('authorization_is_users_own_rls_not_reimplemented', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-rls',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: DenyingResolver(),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      await loop.submitLeg('Request denied key');

      final resolved = store.transcript.lastWhere(
        (turn) => turn['kind'] == 'context_resolved',
      );
      final context = resolved['context'] as Map<String, Object?>;
      expect(context, isEmpty);
    });
  });
}

class _FixedConnectionSubmitPort implements HttpsSubmitPort {
  _FixedConnectionSubmitPort(this.connection);

  final SseConnection connection;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async =>
      connection;
}
