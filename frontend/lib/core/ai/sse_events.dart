import 'taxonomy.dart';

/// Client-side A6 SSE event kinds as received (no model-output reshape).
sealed class SseEvent {
  const SseEvent();
}

/// Opening event — carries the request reference (§5.5 rule 1).
final class AcceptedEvent extends SseEvent {
  const AcceptedEvent({required this.requestReference});

  final String requestReference;
}

/// Idle keep-alive (§5.5 rule 3).
final class HeartbeatEvent extends SseEvent {
  const HeartbeatEvent();
}

/// Typed content chunk as relayed (§5.5 rule 2; A3 kinds).
final class ContentChunkEvent extends SseEvent {
  const ContentChunkEvent({required this.kind, required this.payload});

  final String kind;
  final Object? payload;
}

/// Terminal — validated result (§5.5 rule 4).
final class CompletedEvent extends SseEvent {
  const CompletedEvent({required this.result});

  final Object? result;
}

/// Terminal — §5.4 taxonomy failure (§5.5 rule 4).
final class FailedEvent extends SseEvent {
  const FailedEvent({
    required this.code,
    this.requestReference,
    this.traceId,
    this.retrySafe = false,
  });

  /// Wire-boundary constructor — applies [classifyTaxonomyCode] so unknown codes
  /// never surface raw (FR-010). Prefer this for port implementations.
  factory FailedEvent.fromWire(
    String wireCode, {
    String? requestReference,
    String? traceId,
    bool retrySafe = false,
  }) =>
      FailedEvent(
        code: classifyTaxonomyCode(wireCode),
        requestReference: requestReference,
        traceId: traceId,
        retrySafe: retrySafe,
      );

  final TaxonomyCode code;
  final String? requestReference;
  final String? traceId;
  final bool retrySafe;
}

/// Terminal — client closed the stream (§5.5 rule 5).
///
/// The platform never writes this to a live socket (§5.4 `cancelled` / 499 note);
/// the SDK synthesizes [CancelledTerminal] locally when the caller cancels.
/// Kept as a defensive wire parse for get-request / replay paths that may still
/// materialize the journaled code as an event-shaped value in tests.
final class CancelledEvent extends SseEvent {
  const CancelledEvent();
}

/// Terminal — conversational context request (H-band §2.3 extension; not a taxonomy code).
///
/// Postdates the E2 single-shot freeze; retained on disk as an allowed contract
/// extension per delivery plan §2.3.
final class ContextRequestedEvent extends SseEvent {
  const ContextRequestedEvent({required this.contextRequest});

  final List<Map<String, Object?>> contextRequest;
}

/// Surfaced terminal state after stream consumption.
sealed class TerminalState {
  const TerminalState();
}

final class CompletedTerminal extends TerminalState {
  const CompletedTerminal({required this.result});

  final Object? result;
}

final class FailedTerminal extends TerminalState {
  const FailedTerminal({
    required this.code,
    this.requestReference,
    this.traceId,
    this.retrySafe = false,
  });

  final TaxonomyCode code;
  final String? requestReference;
  final String? traceId;
  final bool retrySafe;
}

final class CancelledTerminal extends TerminalState {
  const CancelledTerminal();
}

/// Stream ended (or errored) without a terminal event and without a local cancel.
///
/// Carries the last recorded request reference so callers can offer a manual
/// retry (§5.5 rule 5) without catching bare [StateError].
final class StreamDroppedTerminal extends TerminalState {
  const StreamDroppedTerminal({
    this.requestReference,
    this.cause,
  });

  final String? requestReference;
  final Object? cause;

  /// Connection loss mid-generation is independently retryable.
  bool get retrySafe => true;
}

/// Terminal — conversational context request (H-band §2.3 extension).
final class ContextRequestedTerminal extends TerminalState {
  const ContextRequestedTerminal({required this.contextRequest});

  final List<Map<String, Object?>> contextRequest;
}
