import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ports.dart';
import 'sse_events.dart';
import 'taxonomy.dart';

/// Production [HttpsSubmitPort]: HTTPS `POST /v1/requests` with A6 headers and SSE stream.
class PlatformHttpsSubmitPort implements HttpsSubmitPort {
  PlatformHttpsSubmitPort({
    required String platformBaseUrl,
    http.Client? httpClient,
  })  : _baseUrl = platformBaseUrl.endsWith('/')
            ? platformBaseUrl.substring(0, platformBaseUrl.length - 1)
            : platformBaseUrl,
        _client = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/v1/requests');
    final body = jsonEncode({
      'capability_id': input.capabilityId,
      'capability_version': input.capabilityVersion,
      'user_intent': input.intent,
      'context': input.context,
      if (input.conversationId != null) 'conversation_id': input.conversationId,
      if (input.turnOrdinal != null) 'turn_ordinal': input.turnOrdinal,
      if (input.transcript != null) 'transcript': input.transcript,
    });

    final response = await _client.send(
      http.Request('POST', uri)
        ..headers.addAll({
          'content-type': 'application/json',
          'authorization': 'Bearer ${headers.aat}',
          'x-idempotency-key': headers.idempotencyKey,
          'x-trace-id': headers.traceId,
          'x-capability-version': headers.capabilityVersion,
          'accept': 'text/event-stream',
        })
        ..body = body,
    );

    final contentType = response.headers['content-type'] ?? '';
    if (response.statusCode < 200 || response.statusCode >= 300 || !contentType.contains('text/event-stream')) {
      final responseBody = await http.Response.fromStream(response);
      throw _mapPreStreamHttpError(responseBody);
    }

    return _HttpSseConnection(response: response);
  }

  PlatformHttpException _mapPreStreamHttpError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final code = classifyTaxonomyCode(decoded['code']?.toString() ?? '');
        return PlatformHttpException(
          code: code,
          requestReference: decoded['request_reference']?.toString(),
          traceId: decoded['trace_id']?.toString(),
          retrySafe: decoded['retry_safe'] == true,
          missingKeys: (decoded['missing_keys'] as List?)?.map((e) => e.toString()).toList(),
          shapes: decoded['shapes'] is Map<String, Object?>
              ? Map<String, Object?>.from(decoded['shapes'] as Map)
              : decoded['shapes'] is Map
                  ? Map<String, Object?>.from(decoded['shapes'] as Map)
                  : null,
          manifestVersion: decoded['manifest_version']?.toString(),
          manifestCapabilityId: decoded['manifest_capability_id']?.toString(),
        );
      }
    } on FormatException {
      // Fall through to transport failure for non-taxonomy bodies.
    }
    throw const TransportFailure();
  }
}

/// Streaming SSE connection over an open HTTP response body.
class _HttpSseConnection implements SseConnection {
  _HttpSseConnection({required http.StreamedResponse response})
      : _controller = StreamController<SseEvent>() {
    _parser = _SseLineParser(_controller);
    _buffer = '';
    _subscription = response.stream.listen(
      (chunk) {
        _buffer += utf8.decode(chunk);
        final parts = _buffer.split('\n');
        _buffer = parts.removeLast();
        for (final line in parts) {
          _parser.addLine(line);
        }
      },
      onDone: () {
        if (_buffer.isNotEmpty) {
          _parser.addLine(_buffer);
          _buffer = '';
        }
        _parser.close();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
          _controller.close();
        }
      },
      cancelOnError: false,
    );
  }

  final StreamController<SseEvent> _controller;
  late final StreamSubscription<List<int>> _subscription;
  late final _SseLineParser _parser;
  late String _buffer;
  var _closed = false;

  @override
  Stream<SseEvent> get events => _controller.stream;

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_subscription.cancel());
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

class _SseLineParser {
  _SseLineParser(this._sink);

  final StreamController<SseEvent> _sink;
  String? _eventType;
  final StringBuffer _dataBuffer = StringBuffer();
  var _closed = false;

  void addLine(String line) {
    if (_closed || _sink.isClosed) {
      return;
    }
    if (line.isEmpty) {
      _emitBlock();
      return;
    }
    if (line.startsWith('event:')) {
      _eventType = line.substring('event:'.length).trim();
    } else if (line.startsWith('data:')) {
      _dataBuffer.write(line.substring('data:'.length).trim());
    }
  }

  void close() {
    _closed = true;
    _emitBlock();
    if (!_sink.isClosed) {
      _sink.close();
    }
  }

  void _emitBlock() {
    final type = _eventType;
    final dataText = _dataBuffer.toString();
    _eventType = null;
    _dataBuffer.clear();
    if (type == null || dataText.isEmpty || _sink.isClosed) {
      return;
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(dataText);
      if (decoded is! Map) {
        return;
      }
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return;
    }

    final event = _mapWireEvent(type, data);
    if (event != null) {
      _sink.add(event);
    }
  }

  SseEvent? _mapWireEvent(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'accepted':
        final reference = data['request_reference']?.toString();
        if (reference == null || reference.isEmpty) {
          return null;
        }
        return AcceptedEvent(requestReference: reference);
      case 'heartbeat':
        return const HeartbeatEvent();
      case 'text_delta':
      case 'partial_structured':
      case 'usage':
      case 'provider_note':
        return ContentChunkEvent(kind: type, payload: data);
      case 'completed':
        return CompletedEvent(result: data['result'] ?? data);
      case 'failed':
        return FailedEvent.fromWire(
          data['code']?.toString() ?? 'internal_error',
          requestReference: data['request_reference']?.toString(),
          traceId: data['trace_id']?.toString(),
          retrySafe: data['retry_safe'] == true,
        );
      case 'cancelled':
        return const CancelledEvent();
      case 'context_requested':
        final raw = data['context_request'];
        if (raw is List) {
          return ContextRequestedEvent(
            contextRequest: raw.map((entry) => Map<String, Object?>.from(entry as Map)).toList(),
          );
        }
        return null;
      default:
        return null;
    }
  }
}
