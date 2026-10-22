import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/sse_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Client that answers every submit with the given byte stream as SSE.
class _SseClient extends http.BaseClient {
  _SseClient(this._body);

  final Stream<List<int>> _body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_body, 200, headers: {
      'content-type': 'text/event-stream',
      'aip-contract-version': '1',
    });
  }
}

const _input = CapabilityInvokeInput(
  capabilityId: 'cap',
  capabilityVersion: '1',
  intent: 'intent',
  context: {},
);

const _headers = SubmitRequestHeaders(
  idempotencyKey: 'idem',
  traceId: 'trace',
  capabilityVersion: '1',
  aat: 'aat',
);

Future<SseConnection> _connect(Stream<List<int>> body) {
  final port = PlatformHttpsSubmitPort(
    platformBaseUrl: 'https://example.test',
    httpClient: _SseClient(body),
  );
  return port.submit(input: _input, headers: _headers);
}

const _arabicPayload =
    'event: text_delta\ndata: {"text": "مرحبا بالعالم"}\n\n'
    'event: completed\ndata: {"result": {"answer": "الحمد لله"}}\n\n';

/// Returns the byte offset that falls inside the first multibyte character.
int _insideMultibyteOffset(List<int> bytes) {
  for (var i = 0; i < bytes.length; i++) {
    // A UTF-8 lead byte is 0b11xxxxxx; the byte after it is a continuation byte.
    if (bytes[i] >= 0xC0 && i + 1 < bytes.length) {
      return i + 1;
    }
  }
  fail('payload has no multibyte character');
}

void main() {
  test(
      'R7-T3: Arabic SSE payload split across byte chunks yields the same events as unsplit',
      () async {
    final bytes = utf8.encode(_arabicPayload);
    final split = _insideMultibyteOffset(bytes);

    Future<List<SseEvent>> collect(List<List<int>> chunks) async {
      final conn = await _connect(Stream.fromIterable(chunks));
      return conn.events.toList();
    }

    final unsplit = await collect([bytes]);
    final splitEvents = await collect([
      bytes.sublist(0, split),
      bytes.sublist(split),
    ]);

    expect(unsplit, hasLength(2));
    expect(splitEvents, hasLength(unsplit.length));
    expect(
      (splitEvents[0] as ContentChunkEvent).payload,
      equals((unsplit[0] as ContentChunkEvent).payload),
    );
    expect(
      (splitEvents[0] as ContentChunkEvent).payload,
      equals({'text': 'مرحبا بالعالم'}),
    );
    expect(
      (splitEvents[1] as CompletedEvent).result,
      equals({'answer': 'الحمد لله'}),
    );
  });

  test(
      'R7-T3: malformed UTF-8 yields one observed failure and no late or double terminal',
      () async {
    final bytes = <int>[
      ...utf8.encode('event: heartbeat\ndata: {}\n\n'),
      0xFF, 0xFE, 0x0A, // invalid UTF-8 sequence
      ...utf8.encode('event: completed\ndata: {"result": {}}\n\n'),
    ];

    final conn = await _connect(Stream.value(bytes));
    final seen = <Object>[];
    final errors = <Object>[];
    final done = Completer<void>();
    conn.events.listen(
      seen.add,
      onError: errors.add,
      onDone: done.complete,
    );
    await done.future.timeout(const Duration(seconds: 5));

    expect(errors, hasLength(1));
    expect(errors.single, isA<FormatException>());
    expect(seen.whereType<CompletedEvent>(), isEmpty);
    expect(seen.whereType<FailedEvent>(), isEmpty);
  });

  test(
      'R7-T3: cancel after split chunk closes subscription without late event',
      () async {
    final source = StreamController<List<int>>();
    final bytes = utf8.encode(_arabicPayload);
    final split = _insideMultibyteOffset(bytes);

    final conn = await _connect(source.stream);
    final events = <SseEvent>[];
    final done = Completer<void>();
    conn.events.listen(events.add, onDone: done.complete);

    source.add(bytes.sublist(0, split));
    await Future<void>.delayed(Duration.zero);
    conn.close();
    await done.future.timeout(const Duration(seconds: 5));

    // Bytes arriving after local cancel must not produce any event.
    source.add(bytes.sublist(split));
    await Future<void>.delayed(Duration.zero);
    await source.close();

    expect(events.whereType<ContentChunkEvent>(), isEmpty);
    expect(events.whereType<CompletedEvent>(), isEmpty);
  });
}
