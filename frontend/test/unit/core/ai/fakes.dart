import 'dart:async';
import 'dart:collection';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';

/// In-memory mint fake with call counting.
class FakeMintPort implements AatMintPort {
  FakeMintPort({List<String>? tokens})
      : _tokens = Queue<String>.from(tokens ?? ['aat-token-1', 'aat-token-2']);

  final Queue<String> _tokens;
  int mintCallCount = 0;

  @override
  Future<String> mint() async {
    mintCallCount++;
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
  });

  final TaxonomyCode code;
  final String? requestReference;
  final String? traceId;
  final bool retrySafe;
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
  bool cancelEndpointCalled = false;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    submitCallCount++;
    idempotencyKeys.add(headers.idempotencyKey);
    headerLog.add(headers);

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
        ):
        throw PlatformHttpException(
          code: code,
          requestReference: requestReference,
          traceId: traceId,
          retrySafe: retrySafe,
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
      _controller.add(const CancelledEvent());
      _controller.close();
    }
  }
}

/// Delayed stream for cancel tests — stays open until closed.
class DelayedFakeSseConnection implements SseConnection {
  DelayedFakeSseConnection({
    required SseEvent accepted,
    Duration holdDuration = const Duration(seconds: 30),
  })  : _accepted = accepted,
        _holdDuration = holdDuration,
        _controller = StreamController<SseEvent>();

  final SseEvent _accepted;
  final Duration _holdDuration;
  final StreamController<SseEvent> _controller;
  var closeCallCount = 0;

  @override
  Stream<SseEvent> get events {
    Future.microtask(() async {
      if (!_controller.isClosed) {
        _controller.add(_accepted);
      }
      await Future<void>.delayed(_holdDuration);
    });
    return _controller.stream;
  }

  @override
  void close() {
    closeCallCount++;
    if (!_controller.isClosed) {
      _controller.add(const CancelledEvent());
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
class FakeContextProviderPort {
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
