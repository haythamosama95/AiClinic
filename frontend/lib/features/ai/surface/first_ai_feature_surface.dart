import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'provisional_prose_view.dart';
import 'request_reference_view.dart';

/// First capability surface: `clinic.visit_summary` / `prose` / `advisory_display`.
const kFirstAiCapabilityId = 'clinic.visit_summary';
const kFirstAiCapabilityVersion = '1.0.0';
const kFirstAiIntent = 'generate';

const kAiAcceptKey = Key('ai_accept');
const kAiDiscardKey = Key('ai_discard');
const kAiTerminalProseKey = Key('ai_terminal_prose');
const kAiAcknowledgedKey = Key('ai_acknowledged');

/// Probe for persistence assertions in widget tests (§6.4 inv. 2).
abstract class AiPersistenceProbe {
  void recordWrite(String key, Object? value);

  List<MapEntry<String, Object?>> get writes;
}

/// Probe for export assertions in widget tests (§6.4 inv. 2).
abstract class AiExportProbe {
  void recordExport(Object? payload);

  List<Object?> get exports;
}

class InMemoryAiPersistenceProbe implements AiPersistenceProbe {
  final List<MapEntry<String, Object?>> _writes = [];

  @override
  void recordWrite(String key, Object? value) {
    _writes.add(MapEntry(key, value));
  }

  @override
  List<MapEntry<String, Object?>> get writes => List.unmodifiable(_writes);
}

class InMemoryAiExportProbe implements AiExportProbe {
  final List<Object?> _exports = [];

  @override
  void recordExport(Object? payload) {
    _exports.add(payload);
  }

  @override
  List<Object?> get exports => List.unmodifiable(_exports);
}

enum _SurfacePhase { loading, streaming, completed, failed, acknowledged, discarded }

class FirstAiFeatureSurface extends StatefulWidget {
  const FirstAiFeatureSurface({
    super.key,
    required this.sdk,
    required this.resolver,
    required this.visitId,
    this.persistenceProbe,
    this.exportProbe,
    this.autoInvoke = true,
  });

  final AiClientSdk sdk;
  final ContextResolver resolver;
  final String visitId;
  final AiPersistenceProbe? persistenceProbe;
  final AiExportProbe? exportProbe;
  final bool autoInvoke;

  @override
  State<FirstAiFeatureSurface> createState() => _FirstAiFeatureSurfaceState();
}

class _FirstAiFeatureSurfaceState extends State<FirstAiFeatureSurface> {
  _SurfacePhase _phase = _SurfacePhase.loading;
  String? _provisionalText;
  String? _terminalText;
  String? _requestReference;
  TaxonomyCode? _failureCode;
  StreamSubscription<SseEvent>? _eventSubscription;
  AiInvokeSession? _session;

  @override
  void initState() {
    super.initState();
    if (widget.autoInvoke) {
      unawaited(_invoke());
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _session?.cancel();
    widget.resolver.dispose();
    super.dispose();
  }

  Future<void> _invoke() async {
    setState(() {
      _phase = _SurfacePhase.loading;
      _provisionalText = null;
      _terminalText = null;
      _requestReference = null;
      _failureCode = null;
    });

    final resolveResult = await widget.resolver.resolve([visitChiefComplaintV1Key]);
    if (resolveResult is ContextResolveFailure) {
      _setFailed(code: TaxonomyCode.contextInvalid, requestReference: widget.sdk.lastRequestReference ?? 'ctx-fail');
      return;
    }

    final contextPayload = (resolveResult as ContextResolveSuccess).payload;

    try {
      final session = await widget.sdk.invoke(
        CapabilityInvokeInput(
          capabilityId: kFirstAiCapabilityId,
          capabilityVersion: kFirstAiCapabilityVersion,
          intent: kFirstAiIntent,
          context: {'visit_id': widget.visitId, ...contextPayload},
        ),
      );
      _session = session;
      _eventSubscription = session.events.listen((event) {
        switch (event) {
          case ContentChunkEvent(:final kind, :final payload):
            if (_phase == _SurfacePhase.completed ||
                _phase == _SurfacePhase.failed ||
                _phase == _SurfacePhase.acknowledged ||
                _phase == _SurfacePhase.discarded) {
              return;
            }
            if (kind == 'text_delta') {
              final chunk = provisionalChunkText(payload);
              if (chunk != null) {
                setState(() {
                  _phase = _SurfacePhase.streaming;
                  _provisionalText = chunk;
                });
              }
            }
          case AcceptedEvent(:final requestReference):
            _requestReference = requestReference;
          case CompletedEvent(:final result):
            _onTerminal(CompletedTerminal(result: result));
          case FailedEvent(:final code, :final requestReference, :final traceId, :final retrySafe):
            _onTerminal(
              FailedTerminal(code: code, requestReference: requestReference, traceId: traceId, retrySafe: retrySafe),
            );
          case ContextRequestedEvent(:final contextRequest):
            _onTerminal(ContextRequestedTerminal(contextRequest: contextRequest));
          case HeartbeatEvent():
          case CancelledEvent():
            break;
        }
      });
      unawaited(session.terminal);
    } on PlatformHttpException catch (error) {
      _setFailed(code: error.code, requestReference: error.requestReference);
    } catch (e, st) {
      debugPrint('FirstAiFeatureSurface invoke failed: $e\n$st');
      _setFailed(code: TaxonomyCode.internalError, requestReference: widget.sdk.lastRequestReference ?? 'invoke-error');
    }
  }

  void _onTerminal(TerminalState terminal) {
    if (!mounted) {
      return;
    }
    switch (terminal) {
      case CompletedTerminal(:final result):
        final text = terminalProseText(result);
        setState(() {
          _phase = _SurfacePhase.completed;
          _provisionalText = null;
          _terminalText = text;
        });
      case FailedTerminal(:final code, :final requestReference):
        _setFailed(code: code, requestReference: requestReference);
      case StreamDroppedTerminal(:final requestReference):
        _setFailed(
          code: TaxonomyCode.internalError,
          requestReference: requestReference,
        );
      case CancelledTerminal():
        break;
      case ContextRequestedTerminal():
        _setFailed(
          code: TaxonomyCode.contextInvalid,
          requestReference: _requestReference ?? widget.sdk.lastRequestReference,
        );
    }
  }

  void _setFailed({required TaxonomyCode code, String? requestReference}) {
    setState(() {
      _phase = _SurfacePhase.failed;
      _failureCode = code;
      _requestReference = requestReference ?? widget.sdk.lastRequestReference;
      _provisionalText = null;
    });
  }

  void _accept() {
    if (_phase != _SurfacePhase.completed || _terminalText == null) {
      return;
    }
    setState(() => _phase = _SurfacePhase.acknowledged);
  }

  void _discard() {
    setState(() {
      _phase = _SurfacePhase.discarded;
      _terminalText = null;
      _provisionalText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phase == _SurfacePhase.loading) const LinearProgressIndicator(),
        if (_provisionalText != null &&
            _phase != _SurfacePhase.completed &&
            _phase != _SurfacePhase.acknowledged &&
            _phase != _SurfacePhase.discarded)
          ProvisionalProseView(text: _provisionalText!),
        if (_terminalText != null)
          Semantics(
            label: 'AI validated answer',
            child: Text(key: kAiTerminalProseKey, _terminalText!, style: AppTypography.body(context)),
          ),
        if (_phase == _SurfacePhase.failed && _requestReference != null)
          RequestReferenceView(requestReference: _requestReference!),
        if (_phase == _SurfacePhase.acknowledged)
          const Text(key: kAiAcknowledgedKey, 'Acknowledged for advisory review.'),
        if (_phase == _SurfacePhase.completed) ...[
          AppButton(key: kAiAcceptKey, onPressed: _accept, child: const Text('Accept')),
          const SizedBox(height: 8),
          AppButton(
            key: kAiDiscardKey,
            onPressed: _discard,
            variant: AppButtonVariant.secondary,
            child: const Text('Discard'),
          ),
        ],
        if (_failureCode != null && _failureCode != TaxonomyCode.contextInvalid) const SizedBox.shrink(),
      ],
    );
  }
}
