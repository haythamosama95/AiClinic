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

/// Default required context keys for the frozen first capability.
///
/// Production hosts SHOULD replace this with the key list from capability
/// discovery (§5.5); the surface never branches the resolver on capability id.
const kFirstAiRequiredContextKeys = <String>[visitChiefComplaintV1Key];

const kAiAcceptKey = Key('ai_accept');
const kAiDiscardKey = Key('ai_discard');
const kAiTerminalProseKey = Key('ai_terminal_prose');
const kAiAcknowledgedKey = Key('ai_acknowledged');
const kAiLocalFailureKey = Key('ai_local_failure');
const kAiIdleKey = Key('ai_idle');
const kAiSurfaceSessionActiveKey = Key('ai_surface_session_active');
const kAiSurfaceLoadingKey = Key('ai_surface_loading');

/// Probe for persistence assertions in widget tests (§6.4 inv. 2).
///
/// The surface never writes through this channel. Streaming calls
/// [recordProvisionalVisible] so the spy is live on the draft path; T16 asserts
/// [writes] stays empty.
abstract class AiPersistenceProbe {
  void recordWrite(String key, Object? value);

  /// Observability hook when provisional draft text is shown (not a write).
  void recordProvisionalVisible(String text);

  List<MapEntry<String, Object?>> get writes;
}

/// Probe for export assertions in widget tests (§6.4 inv. 2).
abstract class AiExportProbe {
  void recordExport(Object? payload);

  /// Observability hook when provisional draft text is shown (not an export).
  void recordProvisionalVisible(String text);

  List<Object?> get exports;
}

class InMemoryAiPersistenceProbe implements AiPersistenceProbe {
  final List<MapEntry<String, Object?>> _writes = [];
  final List<String> provisionalVisibles = [];

  @override
  void recordWrite(String key, Object? value) {
    _writes.add(MapEntry(key, value));
  }

  @override
  void recordProvisionalVisible(String text) {
    provisionalVisibles.add(text);
  }

  @override
  List<MapEntry<String, Object?>> get writes => List.unmodifiable(_writes);
}

class InMemoryAiExportProbe implements AiExportProbe {
  final List<Object?> _exports = [];
  final List<String> provisionalVisibles = [];

  @override
  void recordExport(Object? payload) {
    _exports.add(payload);
  }

  @override
  void recordProvisionalVisible(String text) {
    provisionalVisibles.add(text);
  }

  @override
  List<Object?> get exports => List.unmodifiable(_exports);
}

enum _SurfacePhase {
  idle,
  loading,
  streaming,
  completed,
  failed,
  localFailed,
  acknowledged,
  discarded,
}

class FirstAiFeatureSurface extends StatefulWidget {
  const FirstAiFeatureSurface({
    super.key,
    required this.sdk,
    required this.resolver,
    required this.visitId,
    this.requiredContextKeys = kFirstAiRequiredContextKeys,
    this.persistenceProbe,
    this.exportProbe,
    this.onTerminalFailure,
    this.autoInvoke = true,
  });

  final AiClientSdk sdk;
  final ContextResolver resolver;
  final String visitId;

  /// Context keys from capability discovery (injected; surface does not hardcode
  /// discovery itself). Defaults to the frozen first-capability key list.
  final List<String> requiredContextKeys;

  final AiPersistenceProbe? persistenceProbe;
  final AiExportProbe? exportProbe;

  /// Notifies the host when a platform terminal failure arrives so degraded mode
  /// can apply the §5.4 Client behaviour column.
  final void Function(TaxonomyCode code)? onTerminalFailure;

  final bool autoInvoke;

  @override
  State<FirstAiFeatureSurface> createState() => _FirstAiFeatureSurfaceState();
}

class _FirstAiFeatureSurfaceState extends State<FirstAiFeatureSurface> {
  _SurfacePhase _phase = _SurfacePhase.idle;
  String? _provisionalText;
  String? _terminalText;
  String? _requestReference;
  TaxonomyCode? _failureCode;
  StreamSubscription<SseEvent>? _eventSubscription;
  AiInvokeSession? _session;
  var _sessionListening = false;

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
    // Host owns ContextResolver lifetime (E3 screen-scoped cache).
    super.dispose();
  }

  Future<void> _invoke() async {
    setState(() {
      _phase = _SurfacePhase.loading;
      _provisionalText = null;
      _terminalText = null;
      _requestReference = null;
      _failureCode = null;
      _sessionListening = false;
    });

    final resolveResult = await widget.resolver.resolve(widget.requiredContextKeys);
    if (resolveResult is ContextResolveFailure) {
      _setLocalFailure();
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

      var settledFromEvents = false;
      void settle(TerminalState terminal) {
        if (settledFromEvents) {
          return;
        }
        settledFromEvents = true;
        _onTerminal(terminal);
      }

      // Live draft from chunks; terminal events settle immediately when present.
      // session.terminal is also awaited below for stream-drop / cancel-without-event.
      _eventSubscription = session.events.listen((event) {
        switch (event) {
          case ContentChunkEvent(:final kind, :final payload):
            if (_phase == _SurfacePhase.completed ||
                _phase == _SurfacePhase.failed ||
                _phase == _SurfacePhase.localFailed ||
                _phase == _SurfacePhase.acknowledged ||
                _phase == _SurfacePhase.discarded ||
                _phase == _SurfacePhase.idle) {
              return;
            }
            if (kind == 'text_delta') {
              final chunk = provisionalChunkText(payload);
              if (chunk != null) {
                setState(() {
                  _phase = _SurfacePhase.streaming;
                  _provisionalText = (_provisionalText ?? '') + chunk;
                });
                widget.persistenceProbe?.recordProvisionalVisible(chunk);
                widget.exportProbe?.recordProvisionalVisible(chunk);
              }
            }
          case AcceptedEvent(:final requestReference):
            _requestReference = requestReference;
          case CompletedEvent(:final result):
            settle(CompletedTerminal(result: result));
          case FailedEvent(:final code, :final requestReference, :final traceId, :final retrySafe):
            settle(
              FailedTerminal(
                code: code,
                requestReference: requestReference,
                traceId: traceId,
                retrySafe: retrySafe,
              ),
            );
          case CancelledEvent():
            settle(const CancelledTerminal());
          case ContextRequestedEvent(:final contextRequest):
            settle(ContextRequestedTerminal(contextRequest: contextRequest));
          case HeartbeatEvent():
            break;
        }
      });

      if (mounted) {
        setState(() => _sessionListening = true);
      }

      final terminal = await session.terminal;
      if (!mounted) {
        return;
      }
      // Applies StreamDroppedTerminal / CancelledTerminal when the wire had no
      // terminal event; no-ops if events already settled the surface.
      settle(terminal);
    } on PlatformHttpException catch (error) {
      widget.onTerminalFailure?.call(error.code);
      _setFailed(code: error.code, requestReference: error.requestReference);
    } on InvokeCancelledException {
      _returnToIdle();
    } catch (e, st) {
      debugPrint('FirstAiFeatureSurface invoke failed: $e\n$st');
      _setLocalFailure();
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
        widget.onTerminalFailure?.call(code);
        _setFailed(code: code, requestReference: requestReference);
      case StreamDroppedTerminal(:final requestReference):
        _setFailed(
          code: TaxonomyCode.internalError,
          requestReference: requestReference ?? widget.sdk.lastRequestReference,
        );
      case CancelledTerminal():
        _returnToIdle();
      case ContextRequestedTerminal():
        // single_shot surfaces never receive this (§5.5 rule 4); do not invent
        // context_invalid — show a local failure with any real reference only.
        _setLocalFailure();
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

  void _setLocalFailure() {
    setState(() {
      _phase = _SurfacePhase.localFailed;
      _failureCode = null;
      // Only a real SDK-recorded reference — never fabricate support handles.
      _requestReference = widget.sdk.lastRequestReference;
      _provisionalText = null;
    });
  }

  void _returnToIdle() {
    setState(() {
      _phase = _SurfacePhase.idle;
      _provisionalText = null;
      _terminalText = null;
      _failureCode = null;
      // Keep last known reference for support if one was accepted.
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
        if (_phase == _SurfacePhase.loading)
          Text(
            key: _sessionListening ? kAiSurfaceSessionActiveKey : kAiSurfaceLoadingKey,
            _sessionListening ? 'Waiting for AI…' : 'Loading…',
          ),
        if (_phase == _SurfacePhase.idle)
          const SizedBox.shrink(key: kAiIdleKey),
        if (_provisionalText != null &&
            _phase != _SurfacePhase.completed &&
            _phase != _SurfacePhase.acknowledged &&
            _phase != _SurfacePhase.discarded &&
            _phase != _SurfacePhase.idle)
          ProvisionalProseView(text: _provisionalText!),
        if (_terminalText != null)
          Semantics(
            label: 'AI validated answer',
            child: Text(key: kAiTerminalProseKey, _terminalText!, style: AppTypography.body(context)),
          ),
        if (_phase == _SurfacePhase.failed && _requestReference != null)
          RequestReferenceView(requestReference: _requestReference!),
        if (_phase == _SurfacePhase.failed && _requestReference == null)
          Text(
            key: kAiLocalFailureKey,
            'AI request failed. No request reference is available.',
            style: AppTypography.body(context),
          ),
        if (_phase == _SurfacePhase.localFailed) ...[
          Text(
            key: kAiLocalFailureKey,
            'AI request could not be started on this device.',
            style: AppTypography.body(context),
          ),
          if (_requestReference != null) RequestReferenceView(requestReference: _requestReference!),
        ],
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
      ],
    );
  }
}
