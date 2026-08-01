import 'dart:async';
import 'dart:math';

import 'ports.dart';
import 'sse_events.dart';
import 'taxonomy.dart';

export 'ports.dart';
export 'sse_events.dart';
export 'taxonomy.dart';

/// Transport-only AI Client SDK (§4.1).
class AiClientSdk {
  AiClientSdk({
    required AatMintPort mintPort,
    required HttpsSubmitPort submitPort,
    String Function()? idempotencyKeyFactory,
    String Function()? traceIdFactory,
  })  : _mintPort = mintPort,
        _submitPort = submitPort,
        _idempotencyKeyFactory =
            idempotencyKeyFactory ?? _defaultIdempotencyKey,
        _traceIdFactory = traceIdFactory ?? _defaultTraceId;

  final AatMintPort _mintPort;
  final HttpsSubmitPort _submitPort;
  final String Function() _idempotencyKeyFactory;
  final String Function() _traceIdFactory;

  String? _cachedAat;
  String? _lastRequestReference;

  /// Last request reference retained for support (§4.1).
  String? get lastRequestReference => _lastRequestReference;

  /// Submit a capability request and return a handle to the open SSE stream.
  Future<AiInvokeSession> invoke(CapabilityInvokeInput input) async {
    final idempotencyKey = _idempotencyKeyFactory();
    final traceId = _traceIdFactory();
    var reminted = false;

    while (true) {
      try {
        final aat = await _acquireAat();
        final connection = await _submitPort.submit(
          input: input,
          headers: SubmitRequestHeaders(
            idempotencyKey: idempotencyKey,
            traceId: traceId,
            capabilityVersion: input.capabilityVersion,
            aat: aat,
          ),
        );
        return AiInvokeSession._(
          connection: connection,
          onRequestReference: _recordRequestReference,
        );
      } on PlatformHttpException catch (error) {
        _recordRequestReference(error.requestReference);
        if (error.code == TaxonomyCode.unauthenticated && !reminted) {
          reminted = true;
          _cachedAat = null;
          continue;
        }
        rethrow;
      } on TransportFailure {
        continue;
      }
    }
  }

  Future<String> _acquireAat() async {
    final cached = _cachedAat;
    if (cached != null) {
      return cached;
    }
    final token = await _mintPort.mint();
    _cachedAat = token;
    return token;
  }

  void _recordRequestReference(String? reference) {
    if (reference != null && reference.isNotEmpty) {
      _lastRequestReference = reference;
    }
  }

  static String _defaultIdempotencyKey() {
    final random = Random();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static String _defaultTraceId() {
    final random = Random();
    return List.generate(26, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}

/// In-flight capability invocation with stream consumption helpers.
class AiInvokeSession {
  AiInvokeSession._({
    required SseConnection connection,
    required void Function(String? reference) onRequestReference,
  })  : _connection = connection,
        _onRequestReference = onRequestReference {
    _terminalCompleter = _consumeToTerminal(connection.events);
  }

  final SseConnection _connection;
  final void Function(String? reference) _onRequestReference;
  late final Future<TerminalState> _terminalCompleter;
  var _cancelled = false;

  /// Relayed SSE events as received (no reshape).
  Stream<SseEvent> get events => _connection.events;

  /// Exactly one terminal outcome — never inferred from silence.
  Future<TerminalState> get terminal => _terminalCompleter;

  /// Cancel by closing the stream (§5.5 rule 5).
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _connection.close();
  }

  Future<TerminalState> _consumeToTerminal(Stream<SseEvent> source) async {
    await for (final event in source) {
      switch (event) {
        case AcceptedEvent(:final requestReference):
          _onRequestReference(requestReference);
        case HeartbeatEvent():
          break;
        case ContentChunkEvent():
          break;
        case CompletedEvent(:final result):
          return CompletedTerminal(result: result);
        case FailedEvent(
            :final code,
            :final requestReference,
            :final traceId,
            :final retrySafe,
          ):
          _onRequestReference(requestReference);
          return FailedTerminal(
            code: code,
            requestReference: requestReference,
            traceId: traceId,
            retrySafe: retrySafe,
          );
        case CancelledEvent():
          return const CancelledTerminal();
      }
    }
    throw StateError('SSE stream ended without a terminal event');
  }
}
