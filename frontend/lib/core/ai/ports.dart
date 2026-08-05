import 'sse_events.dart';
import 'taxonomy.dart';

/// Injectable port for acquiring an AAT from the clinic mint path.
abstract class AatMintPort {
  Future<String> mint();
}

/// Input for a single capability invocation (submit surface).
class CapabilityInvokeInput {
  const CapabilityInvokeInput({
    required this.capabilityId,
    required this.capabilityVersion,
    required this.intent,
    required this.context,
    this.conversationId,
    this.turnOrdinal,
    this.transcript,
  });

  final String capabilityId;
  final String capabilityVersion;
  final String intent;
  final Map<String, dynamic> context;

  /// Client-supplied conversation grouping (conversational capabilities only).
  ///
  /// H-band §2.3 extension — postdates the E2 single-shot freeze.
  final String? conversationId;

  /// Client-supplied leg ordinal (conversational capabilities only).
  ///
  /// H-band §2.3 extension — postdates the E2 single-shot freeze.
  final int? turnOrdinal;

  /// Prior transcript turns resupplied on each leg (conversational capabilities only).
  ///
  /// H-band §2.3 extension — postdates the E2 single-shot freeze.
  final List<Map<String, Object?>>? transcript;
}

/// A6 submit-request correlation headers (frozen by A6 / A2).
class SubmitRequestHeaders {
  const SubmitRequestHeaders({
    required this.idempotencyKey,
    required this.traceId,
    required this.capabilityVersion,
    required this.aat,
  });

  final String idempotencyKey;
  final String traceId;
  final String capabilityVersion;
  final String aat;
}

/// Open SSE connection returned by a successful submit.
///
/// [events] may be single-subscription (natural for HTTP SSE). The AI Client
/// SDK rebroadcasts internally so its terminal consumer and any caller listeners
/// do not conflict — port implementers need not expose a broadcast stream.
abstract class SseConnection {
  Stream<SseEvent> get events;

  /// Connection-scoped cancel (§5.5 rule 5) — no separate cancel endpoint.
  void close();
}

/// HTTP-level platform error before an SSE stream opens.
class PlatformHttpException implements Exception {
  const PlatformHttpException({
    required this.code,
    this.requestReference,
    this.traceId,
    this.retrySafe = false,
    this.missingKeys,
    this.shapes,
    this.manifestVersion,
    this.manifestCapabilityId,
  });

  final TaxonomyCode code;
  final String? requestReference;
  final String? traceId;
  final bool retrySafe;

  /// C2 missing-key manifest fields when [code] is [TaxonomyCode.contextRequired].
  final List<String>? missingKeys;
  final Map<String, Object?>? shapes;
  final String? manifestVersion;
  final String? manifestCapabilityId;
}

/// Transport failure before a terminal platform event (retryable by SDK).
class TransportFailure implements Exception {
  const TransportFailure();
}

/// Transport retries exhausted — caller may offer a manual retry with the same key.
class TransportRetryExhausted implements Exception {
  const TransportRetryExhausted({
    required this.idempotencyKey,
    required this.attempts,
  });

  final String idempotencyKey;
  final int attempts;

  @override
  String toString() =>
      'TransportRetryExhausted(idempotencyKey: $idempotencyKey, attempts: $attempts)';
}

/// Submit-phase cancel via [AiClientSdk.invoke]'s `cancelSignal` before a session opens.
class InvokeCancelledException implements Exception {
  const InvokeCancelledException();

  @override
  String toString() => 'InvokeCancelledException';
}

/// Injectable port for HTTPS submit that opens the SSE stream.
abstract class HttpsSubmitPort {
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  });
}
