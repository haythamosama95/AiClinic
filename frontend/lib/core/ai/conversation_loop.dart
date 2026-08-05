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
  Future<TerminalState> submitLeg(
    String userMessage, {
    void Function(AiInvokeSession session)? onSession,
  }) async {
    final leg = _store.prepareLegSubmit(userMessage);
    final session = await _sdk.invoke(
      CapabilityInvokeInput(
        capabilityId: _baseInput.capabilityId,
        capabilityVersion: _baseInput.capabilityVersion,
        intent: _baseInput.intent,
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
    await _handleTerminal(terminal);
    _currentSession = null;
    return terminal;
  }

  /// Cancels only the in-flight leg's stream (§6.7.4).
  void cancelCurrentLeg() {
    _currentSession?.cancel();
  }

  Future<void> _handleTerminal(TerminalState terminal) async {
    switch (terminal) {
      case CompletedTerminal(:final result):
        final text = _extractProse(result);
        if (text != null) {
          _store.appendModelAnswer(text);
        }
      case ContextRequestedTerminal(:final contextRequest):
        _store.appendContextRequested(contextRequest);
        final keys = contextRequest
            .map((entry) => entry['key'] as String)
            .toList(growable: false);
        final resolved = await _resolver.resolve(keys);
        if (resolved is ContextResolveSuccess) {
          _store.appendContextResolved(resolved.payload);
        } else if (resolved is ContextResolveFailure) {
          _store.appendContextResolved(<String, Object?>{});
        }
      case FailedTerminal():
      case CancelledTerminal():
      case StreamDroppedTerminal():
        break;
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
