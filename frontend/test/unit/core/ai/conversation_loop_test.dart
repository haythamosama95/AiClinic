import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ai/conversation_loop.dart';
import 'package:ai_clinic/core/ai/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Conversation loop', () {
    test('continuation_leg_submitted_after_context_requested_with_resolved_payload', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      var keyIndex = 0;
      final keys = ['cont-key-1', 'cont-key-2'];
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-leg-2')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final store = ConversationStore(
        conversationId: 'conv-loop-continue',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: resolver,
        store: store,
        baseInput: conversationalInvokeInput(),
        idempotencyKeyFactory: () => keys[keyIndex++],
      );

      final terminal = await loop.submitLeg('Summarise the visit.');

      expect(terminal, isA<CompletedTerminal>());
      expect(submit.submitCallCount, 2);
      expect(submit.idempotencyKeys, ['cont-key-1', 'cont-key-2']);
      expect(submit.inputs, hasLength(2));

      final continuation = submit.inputs[1];
      expect(continuation.turnOrdinal, greaterThan(submit.inputs[0].turnOrdinal!));
      expect(
        continuation.transcript!.any((turn) => turn['kind'] == 'context_resolved'),
        isTrue,
      );
      final resolvedTurn = continuation.transcript!.firstWhere(
        (turn) => turn['kind'] == 'context_resolved',
      );
      final resolvedContext = resolvedTurn['context'] as Map<String, Object?>;
      expect(resolvedContext.containsKey(visitChiefComplaintV1Key), isTrue);
      expect(
        continuation.transcript!.any((turn) => turn['kind'] == 'user'),
        isTrue,
      );
      expect(
        continuation.transcript!.where((turn) => turn['kind'] == 'user'),
        hasLength(1),
        reason: 'no fabricated second user turn on continuation',
      );
    });

    test('requested_keys_resolved_through_existing_resolver_no_capability_branching',
        () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
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

      expect(submit.submitCallCount, 2);
      expect(resolver.resolveCalls, hasLength(1));
      expect(resolver.resolveCalls.single, [visitChiefComplaintV1Key]);
      expect(resolver.resolveRequestsCalls, hasLength(1));
      expect(
        resolver.resolveRequestsCalls.single.single['key'],
        visitChiefComplaintV1Key,
      );
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_requested'),
        isTrue,
      );
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_resolved'),
        isTrue,
      );
    });

    test('loop_passes_key_and_arguments_to_resolver', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            contextRequestedStream(
              contextRequest: [
                {
                  'key': visitChiefComplaintV1Key,
                  'arguments': <String, Object?>{'patient_hint': 'Ahmed'},
                },
              ],
            ),
          ),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-args')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final store = ConversationStore(
        conversationId: 'conv-loop-args',
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

      await loop.submitLeg('What about Ahmed?');

      expect(resolver.resolveRequestsCalls, hasLength(1));
      final request = resolver.resolveRequestsCalls.single.single;
      expect(request['key'], visitChiefComplaintV1Key);
      expect(
        request['arguments'],
        equals(<String, Object?>{'patient_hint': 'Ahmed'}),
      );
    });

    test('intent_field_carries_typed_message_not_base_intent', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(completedStream(requestReference: 'req-intent')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-intent',
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

      const typed = 'what did we prescribe Ahmed last visit?';
      await loop.submitLeg(typed);

      expect(submit.inputs.single.intent, typed);
      expect(submit.inputs.single.intent, isNot(conversationalInvokeInput().intent));
      expect(submit.inputs.single.transcript, isEmpty);
      expect(submit.inputs.single.turnOrdinal, 1);
    });

    test('wire_resupply_carries_prior_transcript_including_resolved_context', () async {
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-resupply')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-resupply',
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

      await loop.submitLeg('Need context then answer');

      expect(submit.submitCallCount, 2);
      final leg1 = submit.inputs[0];
      final leg2 = submit.inputs[1];
      expect(leg1.transcript, isEmpty);
      expect(leg2.transcript, isNotEmpty);

      final ordinals = leg2.transcript!
          .map((turn) => turn['turn_ordinal'] as int)
          .toList(growable: false);
      expect(ordinals.toSet(), hasLength(ordinals.length));
      for (var i = 1; i < ordinals.length; i++) {
        expect(ordinals[i], greaterThan(ordinals[i - 1]));
      }
      for (final ordinal in ordinals) {
        expect(ordinal, lessThan(leg2.turnOrdinal!));
      }
      expect(
        leg2.transcript!.any((turn) => turn['kind'] == 'context_resolved'),
        isTrue,
      );
      expect(
        leg2.transcript!.any((turn) => turn['kind'] == 'context_requested'),
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
      expect(store.transcript, isEmpty);
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
      expect(store.transcript, isEmpty);

      final second = await loop.submitLeg('Follow-up after cancel');
      expect(second, isA<CompletedTerminal>());
      expect(submit.submitCallCount, 2);
      expect(
        store.transcript.any((turn) => turn['kind'] == 'user'),
        isTrue,
      );
    });

    test('failed_leg_does_not_leave_dangling_user_turn', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.providerUnavailable),
          ),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-fail-dangling',
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

      final terminal = await loop.submitLeg('This will fail');

      expect(terminal, isA<FailedTerminal>());
      expect(store.transcript, isEmpty);
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
      expect(
        store.transcript.any(
          (turn) => turn['kind'] == 'user' && turn['text'] == 'Generate summary',
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

      expect(submit.submitCallCount, 2);
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
      final mint = FakeMintPort(tokens: ['t1', 't2']);
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-after-rls')),
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

      final terminal = await loop.submitLeg('Request denied key');

      expect(terminal, isA<CompletedTerminal>());
      expect(submit.submitCallCount, 2);
      final resolved = store.transcript.lastWhere(
        (turn) => turn['kind'] == 'context_resolved',
      );
      final context = resolved['context'] as Map<String, Object?>;
      expect(context, isEmpty);
    });

    test('context_resolve_failure_does_not_append_or_continue', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(contextRequestedStream()),
          SubmitOpenStreamStep(completedStream(requestReference: 'should-not-run')),
        ],
      );
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final store = ConversationStore(
        conversationId: 'conv-loop-resolve-fail',
        isConversational: true,
      );
      final loop = ConversationLoop(
        sdk: sdk,
        mintPort: mint,
        submitPort: submit,
        resolver: ContextResolver(providerPort: ThrowingContextProviderPort()),
        store: store,
        baseInput: conversationalInvokeInput(),
      );

      final terminal = await loop.submitLeg('Resolver will fail');

      expect(terminal, isA<FailedTerminal>());
      expect(submit.submitCallCount, 1);
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_resolved'),
        isFalse,
      );
      expect(
        store.transcript.any((turn) => turn['kind'] == 'context_requested'),
        isFalse,
      );
      expect(store.transcript, isEmpty);
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
