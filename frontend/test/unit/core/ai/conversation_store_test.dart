import 'dart:io';

import 'package:ai_clinic/core/ai/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('Conversation store', () {
    test('transcript_held_locally_and_resupplied_per_leg', () {
      final store = ConversationStore(
        conversationId: 'conv-store-001',
        isConversational: true,
      );

      final leg1 = store.prepareLegSubmit('What is the chief complaint?');
      expect(leg1.turnOrdinal, 1);
      expect(leg1.transcript, hasLength(1));
      expect(leg1.transcript.first['text'], 'What is the chief complaint?');

      store.appendModelAnswer('Please provide more context.');
      final leg2 = store.prepareLegSubmit('The patient has a headache.');
      expect(leg2.turnOrdinal, 2);
      expect(leg2.transcript, hasLength(3));
      expect(leg2.transcript.last['text'], 'The patient has a headache.');
      expect(
        leg2.transcript.any((turn) => turn['kind'] == 'model'),
        isTrue,
      );
    });

    test('transcript_discarded_on_close', () {
      final store = ConversationStore(
        conversationId: 'conv-store-close',
        isConversational: true,
      );

      store.prepareLegSubmit('Hello');
      store.appendModelAnswer('Hi there.');
      expect(store.transcript, isNotEmpty);

      store.close();
      expect(store.transcript, isEmpty);
      expect(store.isOpen, isFalse);
      expect(
        () => store.prepareLegSubmit('After close'),
        throwsA(isA<StateError>()),
      );
    });

    test('client_never_interprets_message_or_chooses_keys', () {
      final store = ConversationStore(
        conversationId: 'conv-store-spy',
        isConversational: true,
      );

      const rawMessage = 'Need labs for patient 42 — urgent!!!';
      final leg = store.prepareLegSubmit(rawMessage);

      expect(leg.transcript.single['text'], rawMessage);
      expect(leg.transcript.single.containsKey('requested_keys'), isFalse);
      expect(leg.transcript.single.containsKey('capability_id'), isFalse);
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
      final store = ConversationStore(
        conversationId: 'conv-single-shot',
        isConversational: false,
      );

      expect(
        () => store.prepareLegSubmit('Should not attach'),
        throwsA(isA<StateError>()),
      );
      expect(store.transcript, isEmpty);
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
