/// Local transcript hold / resupply / discard for conversational capabilities (§4.1).
class ConversationStore {
  ConversationStore({
    required this.conversationId,
    required this.isConversational,
  });

  final String conversationId;
  final bool isConversational;

  final List<Map<String, Object?>> _transcript = <Map<String, Object?>>[];
  var _open = true;
  String? _pendingUserText;

  bool get isOpen => _open;

  /// Immutable view of the local transcript.
  List<Map<String, Object?>> get transcript =>
      List<Map<String, Object?>>.unmodifiable(_transcript);

  /// Next leg ordinal derived so every transcript turn ordinal is strictly less (§6.7.1).
  int get nextLegOrdinal => _lastTranscriptOrdinal + 1;

  int get _lastTranscriptOrdinal {
    if (_transcript.isEmpty) {
      return 0;
    }
    return _transcript.last['turn_ordinal']! as int;
  }

  /// Records the pending user message for this leg and returns submit fields.
  ///
  /// Does **not** append the user turn yet — that happens only on a successful
  /// terminal (`completed` / successful `context_requested` path). Free text is
  /// forwarded without interpretation or key selection (FR-013).
  LegSubmitContext prepareLegSubmit(String userText) {
    _assertOpen();
    _pendingUserText = userText;
    return LegSubmitContext(
      turnOrdinal: nextLegOrdinal,
      transcript: _snapshotTranscript(),
      intent: userText,
    );
  }

  /// Continuation after successful context resolution — no new user turn.
  LegSubmitContext prepareContinuationSubmit({required String intent}) {
    _assertOpen();
    return LegSubmitContext(
      turnOrdinal: nextLegOrdinal,
      transcript: _snapshotTranscript(),
      intent: intent,
    );
  }

  /// Commits the pending user message into the transcript (success path only).
  void commitPendingUserTurn() {
    _assertOpen();
    final text = _pendingUserText;
    if (text == null) {
      return;
    }
    _pendingUserText = null;
    _appendTurn(<String, Object?>{
      'turn_ordinal': _nextTranscriptOrdinal(),
      'kind': 'user',
      'text': text,
    });
  }

  /// Drops the pending user message without mutating the transcript (fail/cancel).
  void discardPendingUserTurn() {
    _pendingUserText = null;
  }

  void appendModelAnswer(String text) {
    _assertOpen();
    _appendTurn(<String, Object?>{
      'turn_ordinal': _nextTranscriptOrdinal(),
      'kind': 'model',
      'text': text,
    });
  }

  void appendContextRequested(List<Map<String, Object?>> requests) {
    _assertOpen();
    _appendTurn(<String, Object?>{
      'turn_ordinal': _nextTranscriptOrdinal(),
      'kind': 'context_requested',
      'requests': requests,
    });
  }

  void appendContextResolved(Map<String, Object?> context) {
    _assertOpen();
    _appendTurn(<String, Object?>{
      'turn_ordinal': _nextTranscriptOrdinal(),
      'kind': 'context_resolved',
      'context': context,
    });
  }

  /// Discards the transcript when the conversation closes (FR-012).
  void close() {
    _transcript.clear();
    _pendingUserText = null;
    _open = false;
  }

  int _nextTranscriptOrdinal() => _lastTranscriptOrdinal + 1;

  void _appendTurn(Map<String, Object?> turn) {
    _transcript.add(turn);
  }

  List<Map<String, Object?>> _snapshotTranscript() {
    return _transcript
        .map((turn) => Map<String, Object?>.from(turn))
        .toList(growable: false);
  }

  void _assertOpen() {
    if (!_open) {
      throw StateError('Conversation is closed');
    }
    if (!isConversational) {
      throw StateError('Conversation store is only for conversational capabilities');
    }
  }
}

/// Submit context for one conversational leg.
class LegSubmitContext {
  const LegSubmitContext({
    required this.turnOrdinal,
    required this.transcript,
    required this.intent,
  });

  final int turnOrdinal;
  final List<Map<String, Object?>> transcript;

  /// Literal typed message for this leg (§8.10 / A14).
  final String intent;
}
