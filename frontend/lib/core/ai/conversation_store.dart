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
  var _nextLegOrdinal = 1;
  var _nextTranscriptOrdinal = 1;

  bool get isOpen => _open;

  /// Immutable view of the local transcript.
  List<Map<String, Object?>> get transcript =>
      List<Map<String, Object?>>.unmodifiable(_transcript);

  /// Next leg ordinal for submit (1-based, incremented per leg).
  int get nextLegOrdinal => _nextLegOrdinal;

  /// Records the user message for the current leg and returns submit fields.
  ///
  /// Free text is forwarded without interpretation or key selection (FR-013).
  LegSubmitContext prepareLegSubmit(String userText) {
    _assertOpen();
    final turnOrdinal = _nextTranscriptOrdinal;
    _transcript.add(<String, Object?>{
      'turn_ordinal': turnOrdinal,
      'kind': 'user',
      'text': userText,
    });
    _nextTranscriptOrdinal += 1;
    final legOrdinal = _nextLegOrdinal;
    _nextLegOrdinal += 1;
    return LegSubmitContext(
      turnOrdinal: legOrdinal,
      transcript: _snapshotTranscript(),
    );
  }

  void appendModelAnswer(String text) {
    _assertOpen();
    final turnOrdinal = _nextTranscriptOrdinal;
    _transcript.add(<String, Object?>{
      'turn_ordinal': turnOrdinal,
      'kind': 'model',
      'text': text,
    });
    _nextTranscriptOrdinal += 1;
  }

  void appendContextRequested(List<Map<String, Object?>> requests) {
    _assertOpen();
    final turnOrdinal = _nextTranscriptOrdinal;
    _transcript.add(<String, Object?>{
      'turn_ordinal': turnOrdinal,
      'kind': 'context_requested',
      'requests': requests,
    });
    _nextTranscriptOrdinal += 1;
  }

  void appendContextResolved(Map<String, Object?> context) {
    _assertOpen();
    final turnOrdinal = _nextTranscriptOrdinal;
    _transcript.add(<String, Object?>{
      'turn_ordinal': turnOrdinal,
      'kind': 'context_resolved',
      'context': context,
    });
    _nextTranscriptOrdinal += 1;
  }

  /// Discards the transcript when the conversation closes (FR-012).
  void close() {
    _transcript.clear();
    _open = false;
    _nextLegOrdinal = 1;
    _nextTranscriptOrdinal = 1;
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
  });

  final int turnOrdinal;
  final List<Map<String, Object?>> transcript;
}
