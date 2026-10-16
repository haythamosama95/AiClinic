import 'ai_client_sdk.dart';
import 'context_resolver.dart';
import 'conversation_store.dart';

/// Chat negotiation loop: submit legs, resolve context, append transcript (§4.1; §6.7).
class ConversationLoop {
  ConversationLoop({
    required AiClientSdk sdk,
    required AatMintPort mintPort,
    required HttpsSubmitPort submitPort,
    required ContextResolver resolver,
    required ConversationStore store,
    required CapabilityInvokeInput baseInput,
    String Function()? idempotencyKeyFactory,
  })  : _sdk = sdk,
        _mintPort = mintPort,
        _submitPort = submitPort,
        _resolver = resolver,
        _store = store,
        _baseInput = baseInput,
        _idempotencyKeyFactory = idempotencyKeyFactory;

  final AiClientSdk _sdk;
  // Retained for constructor compatibility with H3 call sites; per-invoke
  // idempotency keys mean the loop no longer rebuilds the SDK per leg.
  // ignore: unused_field
  final AatMintPort _mintPort;
  // ignore: unused_field
  final HttpsSubmitPort _submitPort;
  final ContextResolver _resolver;
  final ConversationStore _store;
  final CapabilityInvokeInput _baseInput;
  final String Function()? _idempotencyKeyFactory;

  AiInvokeSession? _currentSession;

  /// Submits one leg with the user message; handles context_requested and completed.
  ///
  /// After a successful context resolution the loop automatically submits the
  /// continuation leg (new idempotency key, resupplied transcript, no fabricated
  /// user turn) until `completed` or a failure/cancel terminal (§8.10).
  Future<TerminalState> submitLeg(
    String userMessage, {
    void Function(AiInvokeSession session)? onSession,
  }) async {
    final leg = _store.prepareLegSubmit(userMessage);
    return _runLeg(leg, onSession: onSession);
  }

  /// Cancels only the in-flight leg's stream (§6.7.4).
  void cancelCurrentLeg() {
    _currentSession?.cancel();
  }

  Future<TerminalState> _runLeg(
    LegSubmitContext leg, {
    void Function(AiInvokeSession session)? onSession,
  }) async {
    final session = await _sdk.invoke(
      CapabilityInvokeInput(
        capabilityId: _baseInput.capabilityId,
        capabilityVersion: _baseInput.capabilityVersion,
        intent: leg.intent,
        context: _baseInput.context,
        conversationId: _store.conversationId,
        turnOrdinal: leg.turnOrdinal,
        transcript: leg.transcript,
      ),
      idempotencyKey: _idempotencyKeyFactory?.call(),
    );
    _currentSession = session;
    onSession?.call(session);
    final terminal = await session.terminal;
    final handled = await _handleTerminal(terminal, legIntent: leg.intent);
    _currentSession = null;
    return handled;
  }

  Future<TerminalState> _handleTerminal(
    TerminalState terminal, {
    required String legIntent,
  }) async {
    switch (terminal) {
      case CompletedTerminal(:final result):
        _store.commitPendingUserTurn();
        final text = _extractProse(result);
        if (text != null) {
          _store.appendModelAnswer(text);
        }
        return terminal;
      case ContextRequestedTerminal(:final contextRequest):
        final resolved = await _resolver.resolveRequests(contextRequest);
        if (resolved is ContextResolveFailure) {
          _store.discardPendingUserTurn();
          return FailedTerminal(
            code: TaxonomyCode.internalError,
            requestReference: _sdk.lastRequestReference,
          );
        }
        final payload = (resolved as ContextResolveSuccess).payload;
        _store.commitPendingUserTurn();
        _store.appendContextRequested(contextRequest);
        _store.appendContextResolved(payload);
        final continuation = _store.prepareContinuationSubmit(intent: legIntent);
        return _runLeg(continuation);
      case FailedTerminal():
      case CancelledTerminal():
      case StreamDroppedTerminal():
        _store.discardPendingUserTurn();
        return terminal;
    }
  }

  String? _extractProse(Object? result) {
    if (result is Map) {
      final content = result['final content'];
      if (content is Map && content['text'] is String) {
        return content['text'] as String;
      }
      if (result['text'] is String) {
        return result['text'] as String;
      }
    }
    if (result is String) {
      return result;
    }
    return null;
  }
}
