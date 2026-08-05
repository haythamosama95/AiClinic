import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ai/taxonomy.dart';

import '../availability/ai_availability.dart';
import '../degraded/ai_degraded_mode.dart';
import '../degraded/ai_degraded_view.dart';
import '../surface/first_ai_feature_surface.dart';

/// Tracks AI-platform network calls for widget spies (T8; FR-009).
abstract class PlatformNetworkSpy {
  int get platformCallCount;

  void recordPlatformCall(String url);
}

class InMemoryPlatformNetworkSpy implements PlatformNetworkSpy {
  int _count = 0;
  final List<String> urls = [];

  @override
  int get platformCallCount => _count;

  @override
  void recordPlatformCall(String url) {
    _count++;
    urls.add(url);
  }
}

/// Dependencies injectable by widget tests and production / CP3 composition.
///
/// Production hosts SHOULD construct [contextProvider] as a per-visit
/// `SupabaseContextProviderPort(client: …, visitId: visitId)` so the
/// argument-free [ContextProviderPort.fetchVisitChiefComplaint] can reach
/// `public.get_visit_chief_complaint`. Widget tests may inject
/// `HarnessContextProviderPort` instead.
///
/// [requiredContextKeys] SHOULD come from capability discovery (§5.5); the
/// default is the frozen first-capability key list.
class AiFeatureHostDependencies {
  const AiFeatureHostDependencies({
    required this.availabilityReader,
    required this.reachabilityPort,
    required this.sdk,
    required this.contextProvider,
    required this.visitId,
    this.requiredContextKeys = kFirstAiRequiredContextKeys,
    this.networkSpy,
    this.persistenceProbe,
    this.exportProbe,
    this.skipReachabilityProbe = false,
  });

  final AiAvailabilityReader availabilityReader;
  final PlatformReachabilityPort reachabilityPort;
  final AiClientSdk sdk;
  final ContextProviderPort contextProvider;
  final String visitId;
  final List<String> requiredContextKeys;
  final PlatformNetworkSpy? networkSpy;
  final AiPersistenceProbe? persistenceProbe;
  final AiExportProbe? exportProbe;
  final bool skipReachabilityProbe;
}

/// Standalone host composing availability gate + surface (Clarification Q2).
class AiFeatureHostPage extends StatefulWidget {
  const AiFeatureHostPage({super.key, required this.dependencies});

  final AiFeatureHostDependencies dependencies;

  @override
  State<AiFeatureHostPage> createState() => _AiFeatureHostPageState();
}

class _AiFeatureHostPageState extends State<AiFeatureHostPage> {
  AiDegradedMode _mode = AiDegradedMode.nonEnrolled;
  var _loading = true;
  ContextResolver? _resolver;
  bool _platformReachable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _resolver?.dispose();
    _resolver = null;
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final availability = await widget.dependencies.availabilityReader.read();

      if (!availability.enrolled) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _mode = AiDegradedMode.nonEnrolled;
          _platformReachable = false;
        });
        return;
      }

      final baseUrl = availability.platformBaseUrl;
      var reachable = false;
      if (!widget.dependencies.skipReachabilityProbe && baseUrl != null && baseUrl.isNotEmpty) {
        widget.dependencies.networkSpy?.recordPlatformCall('$baseUrl/health');
        reachable = await widget.dependencies.reachabilityPort.isReachable(baseUrl);
      }

      final mode = resolveDegradedMode(
        availability: availability,
        platformReachable: reachable,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _mode = mode;
        _platformReachable = reachable;
        if (mode == AiDegradedMode.ready) {
          _resolver = ContextResolver(providerPort: widget.dependencies.contextProvider);
        }
      });
    } catch (e, st) {
      debugPrint('AiFeatureHostPage bootstrap failed: $e\n$st');
      if (!mounted) {
        return;
      }
      // Fail-closed: treat as non-enrolled so clinical work is never blocked (A11).
      setState(() {
        _loading = false;
        _mode = AiDegradedMode.nonEnrolled;
        _platformReachable = false;
        _resolver = null;
      });
    }
  }

  void _onTerminalFailure(TaxonomyCode code) {
    final mode = resolveDegradedMode(
      availability: const AiAvailability(enrolled: true, platformBaseUrl: null),
      platformReachable: _platformReachable,
      terminalFailureCode: code,
    );
    if (mode == AiDegradedMode.ready) {
      return;
    }
    setState(() {
      _mode = mode;
      if (_hidesSurface(mode)) {
        _resolver?.dispose();
        _resolver = null;
      }
    });
  }

  void _onRetry() {
    setState(() {
      _mode = AiDegradedMode.ready;
      _resolver ??= ContextResolver(providerPort: widget.dependencies.contextProvider);
    });
  }

  static bool _hidesSurface(AiDegradedMode mode) =>
      mode == AiDegradedMode.nonEnrolled ||
      mode == AiDegradedMode.installationSuspended ||
      mode == AiDegradedMode.forbiddenCapability ||
      mode == AiDegradedMode.unreachable ||
      mode == AiDegradedMode.quotaExhausted ||
      mode == AiDegradedMode.aiUnavailable ||
      mode == AiDegradedMode.appUpdate ||
      mode == AiDegradedMode.providerUnavailable;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: Text(key: Key('ai_host_loading'), 'Loading…')),
      );
    }

    // Non-enrolled: hide AI chrome entirely (§4.2; A11) — no banner, no AI app bar.
    if (_mode == AiDegradedMode.nonEnrolled) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final hideSurface = _hidesSurface(_mode);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Feature')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: AiDegradedView(
          mode: _mode,
          onRetry: _mode == AiDegradedMode.providerUnavailable ? _onRetry : null,
          child: hideSurface
              ? const Text('Clinical workflows remain available.')
              : _resolver != null
              ? FirstAiFeatureSurface(
                  sdk: widget.dependencies.sdk,
                  resolver: _resolver!,
                  visitId: widget.dependencies.visitId,
                  requiredContextKeys: widget.dependencies.requiredContextKeys,
                  persistenceProbe: widget.dependencies.persistenceProbe,
                  exportProbe: widget.dependencies.exportProbe,
                  onTerminalFailure: _onTerminalFailure,
                )
              : null,
        ),
      ),
    );
  }
}
