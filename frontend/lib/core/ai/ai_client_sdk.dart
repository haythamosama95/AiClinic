import 'dart:async';
import 'dart:math';

import 'ports.dart';
import 'sse_events.dart';
import 'taxonomy.dart';

export 'ports.dart';
export 'sse_events.dart';
export 'taxonomy.dart';

/// Default transport-retry ceiling (1 initial attempt + 2 retries).
///
/// Implementation choice recorded in the E2 Spec Kit clarifications — architecture
/// authorizes retry on transport errors (§4.1) without naming a numeric bound.
const int kDefaultMaxTransportAttempts = 3;

/// Transport-only AI Client SDK (§4.1).
class AiClientSdk {
  AiClientSdk({
    required AatMintPort mintPort,
    required HttpsSubmitPort submitPort,
    String Function()? idempotencyKeyFactory,
    String Function()? traceIdFactory,
    Duration Function(int attemptAfterFailure)? transportBackoff,
    this.maxTransportAttempts = kDefaultMaxTransportAttempts,
  })  : _mintPort = mintPort,
        _submitPort = submitPort,
        _idempotencyKeyFactory =
            idempotencyKeyFactory ?? _defaultIdempotencyKey,
        _traceIdFactory = traceIdFactory ?? _defaultTraceId,
        _transportBackoff = transportBackoff ?? _defaultTransportBackoff;

  final AatMintPort _mintPort;
  final HttpsSubmitPort _submitPort;
  final String Function() _idempotencyKeyFactory;
  final String Function() _traceIdFactory;
  final Duration Function(int attemptAfterFailure) _transportBackoff;

  /// Maximum submit attempts on [TransportFailure] (inclusive of the first try).
  final int maxTransportAttempts;

  String? _cachedAat;
  Future<String>? _inFlightMint;
  String? _lastRequestReference;

  /// Last request reference retained for support (§4.1).
  String? get lastRequestReference => _lastRequestReference;

  /// Submit a capability request and return a handle to the open SSE stream.
  ///
  /// [idempotencyKey] overrides the constructor factory for this invoke only —
  /// stable across transport retries of this call. [cancelSignal] completing
  /// aborts the submit/retry loop before a session exists.
  Future<AiInvokeSession> invoke(
    CapabilityInvokeInput input, {
    String? idempotencyKey,
    Future<void>? cancelSignal,
  }) async {
    final key = idempotencyKey ?? _idempotencyKeyFactory();
    final traceId = _traceIdFactory();
    var reminted = false;
    var transportAttempts = 0;

    while (true) {
      try {
        final aat = await _raceCancel(_acquireAat(), cancelSignal);
        final connection = await _raceCancel(
          _submitPort.submit(
            input: input,
            headers: SubmitRequestHeaders(
              idempotencyKey: key,
              traceId: traceId,
              capabilityVersion: input.capabilityVersion,
              aat: aat,
            ),
          ),
          cancelSignal,
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
        transportAttempts++;
        if (transportAttempts >= maxTransportAttempts) {
          throw TransportRetryExhausted(
            idempotencyKey: key,
            attempts: transportAttempts,
          );
        }
        await _raceCancel(
          Future<void>.delayed(_transportBackoff(transportAttempts)),
          cancelSignal,
        );
      }
    }
  }

  Future<String> _acquireAat() async {
    final cached = _cachedAat;
    if (cached != null) {
      return cached;
    }
    final inFlight = _inFlightMint;
    if (inFlight != null) {
      return inFlight;
    }
    final future = () async {
      try {
        final token = await _mintPort.mint();
        _cachedAat = token;
        return token;
      } finally {
        _inFlightMint = null;
      }
    }();
    _inFlightMint = future;
    return future;
  }

  void _recordRequestReference(String? reference) {
    if (reference != null && reference.isNotEmpty) {
      _lastRequestReference = reference;
    }
  }

  /// Completes with [work] unless [cancelSignal] finishes first.
  static Future<T> _raceCancel<T>(
    Future<T> work,
    Future<void>? cancelSignal,
  ) {
    if (cancelSignal == null) {
      return work;
    }
    final completer = Completer<T>();
    var settled = false;

    void settleValue(T value) {
      if (settled) {
        return;
      }
      settled = true;
      completer.complete(value);
    }

    void settleError(Object error, StackTrace stackTrace) {
      if (settled) {
        return;
      }
      settled = true;
      completer.completeError(error, stackTrace);
    }

    work.then(settleValue, onError: settleError);
    cancelSignal.then(
      (_) => settleError(const InvokeCancelledException(), StackTrace.current),
      onError: settleError,
    );
    return completer.future;
  }

  static String _defaultIdempotencyKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static String _defaultTraceId() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static Duration _defaultTransportBackoff(int attemptAfterFailure) {
    final baseMs = 100 * (1 << (attemptAfterFailure - 1).clamp(0, 10));
    final capped = baseMs > 800 ? 800 : baseMs;
    final jitterFactor = 1 + (Random.secure().nextDouble() * 0.5 - 0.25);
    return Duration(milliseconds: (capped * jitterFactor).round().clamp(1, 800));
  }
}

/// In-flight capability invocation with stream consumption helpers.
class AiInvokeSession {
  AiInvokeSession._({
    required SseConnection connection,
    required void Function(String? reference) onRequestReference,
  })  : _connection = connection,
        _onRequestReference = onRequestReference {
    _relay = StreamController<SseEvent>.broadcast();
    _sourceSubscription = connection.events.listen(
      (event) {
        if (!_relay.isClosed) {
          _relay.add(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_relay.isClosed) {
          _relay.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_relay.isClosed) {
          _relay.close();
        }
      },
      cancelOnError: false,
    );
    _terminalFuture = _consumeToTerminal(_relay.stream);
  }

  final SseConnection _connection;
  final void Function(String? reference) _onRequestReference;
  late final StreamController<SseEvent> _relay;
  late final StreamSubscription<SseEvent> _sourceSubscription;
  late final Future<TerminalState> _terminalFuture;
  var _cancelled = false;
  String? _seenRequestReference;

  /// Relayed SSE events as received (no reshape). Safe for multiple listeners —
  /// the SDK rebroadcasts even when [SseConnection.events] is single-subscription.
  Stream<SseEvent> get events => _relay.stream;

  /// Exactly one terminal outcome — never inferred from silence.
  Future<TerminalState> get terminal => _terminalFuture;

  /// Cancel by closing the stream (§5.5 rule 5). Synthesizes [CancelledTerminal]
  /// locally — the platform does not write `cancelled` to a live socket.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _connection.close();
  }

  Future<TerminalState> _consumeToTerminal(Stream<SseEvent> source) async {
    try {
      await for (final event in source) {
        switch (event) {
          case AcceptedEvent(:final requestReference):
            _seenRequestReference = requestReference;
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
          case ContextRequestedEvent(:final contextRequest):
            return ContextRequestedTerminal(contextRequest: contextRequest);
        }
      }
      if (_cancelled) {
        return const CancelledTerminal();
      }
      return StreamDroppedTerminal(requestReference: _seenRequestReference);
    } catch (error) {
      if (_cancelled) {
        return const CancelledTerminal();
      }
      return StreamDroppedTerminal(
        requestReference: _seenRequestReference,
        cause: error,
      );
    } finally {
      await _sourceSubscription.cancel();
    }
  }
}
