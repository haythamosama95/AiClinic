import 'dart:async';
import 'dart:collection';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';

/// In-memory mint fake with call counting.
class FakeMintPort implements AatMintPort {
  FakeMintPort({List<String>? tokens})
      : _tokens = Queue<String>.from(tokens ?? ['aat-token-1', 'aat-token-2']);

  final Queue<String> _tokens;
  int mintCallCount = 0;

  /// When set, [mint] awaits this before returning (concurrency tests).
  Completer<void>? gate;

  @override
  Future<String> mint() async {
    mintCallCount++;
    final pendingGate = gate;
    if (pendingGate != null) {
      await pendingGate.future;
    }
    if (_tokens.isEmpty) {
      throw StateError('No more AAT tokens configured');
    }
    return _tokens.removeFirst();
  }
}

/// Scripted submit behaviour for tests.
sealed class SubmitScriptStep {}

final class SubmitTransportFailureStep extends SubmitScriptStep {
  SubmitTransportFailureStep();
}

final class SubmitHttpErrorStep extends SubmitScriptStep {
  SubmitHttpErrorStep({
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
  final List<String>? missingKeys;
  final Map<String, Object?>? shapes;
  final String? manifestVersion;
  final String? manifestCapabilityId;
}

final class SubmitOpenStreamStep extends SubmitScriptStep {
  SubmitOpenStreamStep(this.events);

  final List<SseEvent> events;
}

/// In-memory HTTPS submit fake with spies.
class FakeSubmitPort implements HttpsSubmitPort {
  FakeSubmitPort({List<SubmitScriptStep>? script})
      : _script = Queue<SubmitScriptStep>.from(script ?? const []);

  final Queue<SubmitScriptStep> _script;
  int submitCallCount = 0;
  final List<String> idempotencyKeys = [];
  final List<SubmitRequestHeaders> headerLog = [];
  final List<CapabilityInvokeInput> inputs = [];
  bool cancelEndpointCalled = false;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    submitCallCount++;
    idempotencyKeys.add(headers.idempotencyKey);
    headerLog.add(headers);
    inputs.add(input);

    if (_script.isEmpty) {
      throw StateError('No submit script step configured');
    }

    final step = _script.removeFirst();
    switch (step) {
      case SubmitTransportFailureStep():
        throw const TransportFailure();
      case SubmitHttpErrorStep(
          :final code,
          :final requestReference,
          :final traceId,
          :final retrySafe,
          :final missingKeys,
          :final shapes,
          :final manifestVersion,
          :final manifestCapabilityId,
        ):
        throw PlatformHttpException(
          code: code,
          requestReference: requestReference,
          traceId: traceId,
          retrySafe: retrySafe,
          missingKeys: missingKeys,
          shapes: shapes,
          manifestVersion: manifestVersion,
          manifestCapabilityId: manifestCapabilityId,
        );
      case SubmitOpenStreamStep(:final events):
        return FakeSseConnection(events: events);
    }
  }

  void callCancelEndpoint() {
    cancelEndpointCalled = true;
  }
}

/// Controllable in-memory SSE connection.
///
/// Uses a single-subscription stream (natural for HTTP SSE). The SDK must
/// rebroadcast — fakes deliberately do **not** call `asBroadcastStream()`.
class FakeSseConnection implements SseConnection {
  FakeSseConnection({required List<SseEvent> events})
      : _controller = StreamController<SseEvent>() {
    Future.microtask(() async {
      for (final event in events) {
        if (_controller.isClosed) {
          return;
        }
        _controller.add(event);
      }
      if (!_controller.isClosed) {
        await _controller.close();
      }
    });
  }

  final StreamController<SseEvent> _controller;
  var closeCallCount = 0;

  @override
  Stream<SseEvent> get events => _controller.stream;

  @override
  void close() {
    closeCallCount++;
    if (!_controller.isClosed) {
      // Do not inject CancelledEvent — the real wire never writes cancelled to a
      // live socket (§5.4). The SDK synthesizes CancelledTerminal locally.
      _controller.close();
    }
  }
}

/// Delayed stream for cancel tests — stays open until [close].
class DelayedFakeSseConnection implements SseConnection {
  DelayedFakeSseConnection({
    required SseEvent accepted,
  })  : _accepted = accepted,
        _controller = StreamController<SseEvent>() {
    Future.microtask(() {
      if (!_controller.isClosed) {
        _controller.add(_accepted);
      }
    });
  }

  final SseEvent _accepted;
  final StreamController<SseEvent> _controller;
  var closeCallCount = 0;

  void emitContent(SseEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Close without a terminal event (network drop / silence case).
  void drop() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void fail(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
      _controller.close();
    }
  }

  @override
  Stream<SseEvent> get events => _controller.stream;

  @override
  void close() {
    closeCallCount++;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

CapabilityInvokeInput sampleInvokeInput() => const CapabilityInvokeInput(
      capabilityId: 'draft-note',
      capabilityVersion: '1.0.0',
      intent: 'generate',
      context: {'patient_id': 'p-1'},
    );

List<SseEvent> completedStream({
  String requestReference = 'req-abc',
  Object? result = const {'status': 'ok'},
}) =>
    [
      AcceptedEvent(requestReference: requestReference),
      const HeartbeatEvent(),
      const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'hi'}),
      CompletedEvent(result: result),
    ];

List<SseEvent> failedStream({
  required TaxonomyCode code,
  String requestReference = 'req-fail',
  String? rawCode,
}) =>
    [
      AcceptedEvent(requestReference: requestReference),
      FailedEvent(
        code: code,
        requestReference: requestReference,
        traceId: 'trace-1',
      ),
    ];

List<SseEvent> failedStreamWithUnknownCode({
  String requestReference = 'req-unknown',
}) =>
    [
      AcceptedEvent(requestReference: requestReference),
      const FailedEvent(
        code: TaxonomyCode.internalError,
        requestReference: 'req-unknown',
        traceId: 'trace-1',
      ),
    ];

/// Builds a stream whose failed event carries a raw wire code for classification tests.
List<SseEvent> failedStreamWithRawWireCode(String wireCode) => [
      const AcceptedEvent(requestReference: 'req-raw'),
      FailedEvent(
        code: classifyTaxonomyCode(wireCode),
        requestReference: 'req-raw',
        traceId: 'trace-raw',
      ),
    ];

/// In-memory clinic-read port for context resolver unit and contract tests.
class FakeContextProviderPort implements ContextProviderPort {
  FakeContextProviderPort({
    Map<String, Object?>? chiefComplaintPayload,
  }) : _chiefComplaintPayload = chiefComplaintPayload ??
            const {
              'visit_id': '550e8400-e29b-41d4-a716-446655440000',
              'complaint': 'Headache for two days.',
              'recorded_at': '2026-07-31T12:00:00.000Z',
            };

  final Map<String, Object?> _chiefComplaintPayload;
  int fetchVisitChiefComplaintCallCount = 0;

  @override
  Future<Map<String, Object?>> fetchVisitChiefComplaint() async {
    fetchVisitChiefComplaintCallCount++;
    return Map<String, Object?>.from(_chiefComplaintPayload);
  }
}

/// Injectable C1-shaped active-manifest source returning `{ manifests }`.
class FakeActiveManifestSource {
  FakeActiveManifestSource({required this.manifests});

  final List<Map<String, Object?>> manifests;

  Map<String, Object?> discoveryBody() => {'manifests': manifests};
}

Map<String, Object?> sampleActiveManifest({
  List<Map<String, Object?>>? contextRequirements,
}) =>
    {
      'Identity': {
        'capabilityId': 'clinic.visit_summary',
        'version': '1.0.0',
        'title': 'Visit summary',
        'lifecycleState': 'active',
        'successorId': null,
      },
      'Access': {
        'requiredCapabilityScope': 'ai.visit_summary',
        'minimumPlanTier': 'standard',
        'allowedStaffRoles': ['clinician', 'nurse'],
        'killSwitchFlag': false,
      },
      'Interaction': {
        'interactionMode': 'single_shot',
      },
      'Input': {
        'userIntentShape': 'plain_text',
        'priorTurnShape': null,
        'sizeLimits': {'maxChars': 8000},
        'allowedLanguages': ['en'],
      },
      'Context requirements': contextRequirements ??
          [
            {
              'key': 'visit.chief_complaint@v1',
              'required': true,
              'shapeRef': 'visit.chief_complaint@v1',
              'maxSize': 4096,
              'freshnessHint': 'session',
            },
          ],
      'Prompt binding': {
        'systemInstructionArtifactRef': 'prompt/visit-summary-system@v1',
        'businessRuleFragmentRefs': ['rules/visit-summary@v1'],
        'contextRenderingTemplateRef': 'templates/visit-summary@v1',
        'outputFormatInstructionDerivationRule': 'derive_from_output_mode',
      },
      'Output': {
        'mode': 'prose',
        'outputSchemaRef': null,
        'businessValidationRuleRefs': [],
        'repairPolicy': {'allowed': false, 'maxAttempts': 0},
      },
      'Routing': {
        'routingPolicyRef': 'routing/standard@v1',
        'requiredProviderFeatures': {
          'structuredOutput': false,
          'contextWindow': 32000,
          'language': 'en',
        },
        'latencyClass': 'standard',
        'degradedTierPolicy': 'fallback_chain',
      },
      'Economics': {
        'maxInputTokens': 8000,
        'maxOutputTokens': 1024,
        'perRequestCostCeiling': 9024,
        'quotaWeight': 1,
      },
      'Governance': {
        'acceptanceMode': 'advisory_display',
        'retentionClass': 'diagnostic_30d',
        'evalSuiteRef': 'evals/visit-summary@v1',
      },
    };

Map<String, Object?> manifestWithUnknownContextKey() => sampleActiveManifest(
      contextRequirements: [
        {
          'key': 'patient.demographics@v1',
          'required': true,
          'shapeRef': 'patient.demographics@v1',
          'maxSize': 4096,
          'freshnessHint': 'session',
        },
      ],
    );

CapabilityInvokeInput conversationalInvokeInput({
  String conversationId = 'conv-test-001',
  int turnOrdinal = 1,
  List<Map<String, Object?>>? transcript,
}) =>
    CapabilityInvokeInput(
      capabilityId: 'clinic.chat_assistant',
      capabilityVersion: '1.0.0',
      intent: 'chat',
      context: const {'patient_id': 'p-1'},
      conversationId: conversationId,
      turnOrdinal: turnOrdinal,
      transcript: transcript,
    );

List<SseEvent> contextRequestedStream({
  String requestReference = 'req-ctx',
  List<Map<String, Object?>>? contextRequest,
}) =>
    [
      AcceptedEvent(requestReference: requestReference),
      ContextRequestedEvent(
        contextRequest: contextRequest ??
            [
              {
                'key': visitChiefComplaintV1Key,
                'arguments': <String, Object?>{},
              },
            ],
      ),
    ];

/// Spy for [ManifestRefreshPort] — records refresh call count (J2).
class FakeManifestRefreshPort implements ManifestRefreshPort {
  FakeManifestRefreshPort({Map<String, InteractionMode>? modes})
      : _modes = modes ?? const {};

  final Map<String, InteractionMode> _modes;
  int refreshCallCount = 0;

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }

  @override
  InteractionMode interactionModeFor(String capabilityId) {
    return _modes[capabilityId] ?? InteractionMode.singleShot;
  }
}

SubmitHttpErrorStep contextRequiredErrorStep({
  String requestReference = 'req-ctx-required',
  List<String>? missingKeys,
  Map<String, Object?>? shapes,
  String manifestVersion = '1.0.0',
  String manifestCapabilityId = 'clinic.visit_summary',
  bool nullMissingKeys = false,
}) =>
    SubmitHttpErrorStep(
      code: TaxonomyCode.contextRequired,
      requestReference: requestReference,
      traceId: 'trace-ctx-req',
      retrySafe: true,
      missingKeys: nullMissingKeys
          ? null
          : (missingKeys ?? [visitChiefComplaintV1Key]),
      shapes: nullMissingKeys
          ? null
          : (shapes ??
              {
                visitChiefComplaintV1Key: {
                  'type': 'object',
                  'properties': {
                    'visit_id': {'type': 'string'},
                    'complaint': {'type': 'string'},
                  },
                },
              }),
      manifestVersion: manifestVersion,
      manifestCapabilityId: manifestCapabilityId,
    );

/// Resolver spy that records keys / requests without capability id.
class ResolverSpy extends ContextResolver {
  ResolverSpy({required super.providerPort});

  final List<List<String>> resolveCalls = [];
  final List<List<Map<String, Object?>>> resolveRequestsCalls = [];

  @override
  Future<ContextResolveResult> resolveRequests(
    List<Map<String, Object?>> requests,
  ) async {
    resolveRequestsCalls.add(
      requests
          .map((entry) => Map<String, Object?>.from(entry))
          .toList(growable: false),
    );
    resolveCalls.add(
      requests.map((entry) => entry['key'] as String).toList(growable: false),
    );
    return super.resolveRequests(requests);
  }
}

/// Resolver that yields an empty payload (RLS deny simulation — success, not failure).
class DenyingResolver extends ContextResolver {
  DenyingResolver() : super(providerPort: DenyingContextProviderPort());

  @override
  Future<ContextResolveResult> resolveRequests(
    List<Map<String, Object?>> requests,
  ) async {
    return const ContextResolveSuccess(<String, Object?>{});
  }
}

/// Context provider that returns empty payload (RLS deny simulation).
class DenyingContextProviderPort implements ContextProviderPort {
  @override
  Future<Map<String, Object?>> fetchVisitChiefComplaint() async => {};
}

/// Context provider whose RPC path throws (resolution-failure path).
class ThrowingContextProviderPort implements ContextProviderPort {
  ThrowingContextProviderPort([this.error]);

  final Object? error;

  @override
  Future<Map<String, Object?>> fetchVisitChiefComplaint() async {
    throw error ?? StateError('simulated context provider failure');
  }
}
