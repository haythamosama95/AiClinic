import 'dart:io';

import 'package:ai_clinic/core/ai/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Conversation store', () {
    test('transcript_held_locally_and_resupplied_per_leg', () {
      final store = ConversationStore(conversationId: 'conv-store-001', isConversational: true);

      final leg1 = store.prepareLegSubmit('What is the chief complaint?');
      expect(leg1.turnOrdinal, 1);
      expect(leg1.transcript, isEmpty);
      expect(leg1.intent, 'What is the chief complaint?');

      store.commitPendingUserTurn();
      store.appendModelAnswer('Please provide more context.');
      final leg2 = store.prepareLegSubmit('The patient has a headache.');
      expect(leg2.turnOrdinal, 3);
      expect(leg2.transcript, hasLength(2));
      expect(leg2.intent, 'The patient has a headache.');
      expect(leg2.transcript.last['text'], 'Please provide more context.');
      expect(leg2.transcript.any((turn) => turn['kind'] == 'model'), isTrue);
    });

    test('transcript_wire_ordinals_strictly_less_than_leg_ordinal', () {
      final store = ConversationStore(conversationId: 'conv-store-wire', isConversational: true);

      final leg1 = store.prepareLegSubmit('First question');
      _assertWireOrdinalRule(leg1);

      store.commitPendingUserTurn();
      store.appendModelAnswer('First answer');
      store.appendContextRequested([
        {'key': 'visit.chief_complaint@v1', 'arguments': <String, Object?>{}},
      ]);
      store.appendContextResolved({'visit.chief_complaint@v1': <String, Object?>{}});

      final leg2 = store.prepareLegSubmit('Follow-up');
      _assertWireOrdinalRule(leg2);

      store.commitPendingUserTurn();
      store.appendModelAnswer('Follow-up answer');

      final leg3 = store.prepareContinuationSubmit(intent: 'Follow-up');
      _assertWireOrdinalRule(leg3);
    });

    test('prepare_leg_submit_intent_is_typed_message_empty_transcript_on_leg_one', () {
      final store = ConversationStore(conversationId: 'conv-store-intent', isConversational: true);

      const typed = 'what did we prescribe Ahmed last visit?';
      final leg = store.prepareLegSubmit(typed);

      expect(leg.intent, typed);
      expect(leg.turnOrdinal, 1);
      expect(leg.transcript, isEmpty);
      expect(store.transcript, isEmpty);
    });

    test('failed_or_cancelled_leg_leaves_transcript_unchanged_no_dangling_user_turn', () {
      final store = ConversationStore(conversationId: 'conv-store-dangling', isConversational: true);

      store.prepareLegSubmit('Will cancel');
      expect(store.transcript, isEmpty);

      store.discardPendingUserTurn();
      expect(store.transcript, isEmpty);

      store.prepareLegSubmit('Will fail');
      store.discardPendingUserTurn();
      expect(store.transcript, isEmpty);
    });

    test('transcript_discarded_on_close', () {
      final store = ConversationStore(conversationId: 'conv-store-close', isConversational: true);

      store.prepareLegSubmit('Hello');
      store.commitPendingUserTurn();
      store.appendModelAnswer('Hi there.');
      expect(store.transcript, isNotEmpty);

      store.close();
      expect(store.transcript, isEmpty);
      expect(store.isOpen, isFalse);
      expect(() => store.prepareLegSubmit('After close'), throwsA(isA<StateError>()));
    });

    test('client_never_interprets_message_or_chooses_keys', () {
      final store = ConversationStore(conversationId: 'conv-store-spy', isConversational: true);

      const rawMessage = 'Need labs for patient 42 — urgent!!!';
      final leg = store.prepareLegSubmit(rawMessage);

      expect(leg.intent, rawMessage);
      expect(leg.transcript, isEmpty);
      store.commitPendingUserTurn();
      expect(store.transcript.single['text'], rawMessage);
      expect(store.transcript.single.containsKey('requested_keys'), isFalse);
      expect(store.transcript.single.containsKey('capability_id'), isFalse);
    });

    test('no_prompt_provider_or_model_in_conversation_store', () async {
      final result = await Process.run(
        'dart',
        ['run', 'tool/architecture_guard/architecture_guard.dart'],
        workingDirectory: _frontendRoot(),
        runInShell: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('architecture_guard: clean'));
    });

    test('single_shot_unaffected_by_h3', () {
      final store = ConversationStore(conversationId: 'conv-single-shot', isConversational: false);

      expect(() => store.prepareLegSubmit('Should not attach'), throwsA(isA<StateError>()));
      expect(store.transcript, isEmpty);
    });
  });
}

void _assertWireOrdinalRule(LegSubmitContext leg) {
  final ordinals = leg.transcript
      .map((turn) => turn['turn_ordinal'] as int)
      .toList(growable: false);
  expect(ordinals.toSet(), hasLength(ordinals.length), reason: 'duplicate turn_ordinal');
  for (var i = 1; i < ordinals.length; i++) {
    expect(ordinals[i], greaterThan(ordinals[i - 1]), reason: 'not strictly increasing');
  }
  for (final ordinal in ordinals) {
    expect(ordinal, lessThan(leg.turnOrdinal), reason: 'transcript ordinal must be < leg ordinal');
  }
}

String _frontendRoot() {
  final dir = Directory.current;
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    return dir.path;
  }
  return '${dir.path}/frontend';
}
