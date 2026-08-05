import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';

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

/// Dependencies injectable by widget tests and production wiring.
///
/// Production hosts SHOULD construct [contextProvider] as a per-visit
/// `SupabaseContextProviderPort(client: …, visitId: visitId)` so the
/// argument-free [ContextProviderPort.fetchVisitChiefComplaint] can reach
/// `public.get_visit_chief_complaint`. Widget tests may inject
/// `HarnessContextProviderPort` instead.
class AiFeatureHostDependencies {
  const AiFeatureHostDependencies({
    required this.availabilityReader,
    required this.reachabilityPort,
    required this.sdk,
    required this.contextProvider,
    required this.visitId,
    this.networkSpy,
    this.persistenceProbe,
    this.exportProbe,
    this.terminalFailureCode,
    this.skipReachabilityProbe = false,
  });

  final AiAvailabilityReader availabilityReader;
  final PlatformReachabilityPort reachabilityPort;
  final AiClientSdk sdk;
  final ContextProviderPort contextProvider;
  final String visitId;
  final PlatformNetworkSpy? networkSpy;
  final AiPersistenceProbe? persistenceProbe;
  final AiExportProbe? exportProbe;
  final TaxonomyCode? terminalFailureCode;
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
    final availability = await widget.dependencies.availabilityReader.read();

    if (!availability.enrolled) {
      setState(() {
        _loading = false;
        _mode = AiDegradedMode.nonEnrolled;
      });
      return;
    }

    final baseUrl = availability.platformBaseUrl;
    var reachable = false;
    if (!widget.dependencies.skipReachabilityProbe && baseUrl != null && baseUrl.isNotEmpty) {
      widget.dependencies.networkSpy?.recordPlatformCall('$baseUrl/health');
      reachable = await widget.dependencies.reachabilityPort.isReachable(baseUrl);
    }

    final failureCode = widget.dependencies.terminalFailureCode;
    final mode = resolveDegradedMode(
      availability: availability,
      platformReachable: reachable,
      terminalFailureCode: failureCode,
    );

    setState(() {
      _loading = false;
      _mode = mode;
      if (mode == AiDegradedMode.ready) {
        _resolver = ContextResolver(providerPort: widget.dependencies.contextProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hideSurface =
        _mode == AiDegradedMode.nonEnrolled ||
        _mode == AiDegradedMode.installationSuspended ||
        _mode == AiDegradedMode.forbiddenCapability ||
        _mode == AiDegradedMode.unreachable ||
        _mode == AiDegradedMode.quotaExhausted ||
        _mode == AiDegradedMode.aiUnavailable;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Feature')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: AiDegradedView(
          mode: _mode,
          child: hideSurface
              ? const Text('Clinical workflows remain available.')
              : _resolver != null
              ? FirstAiFeatureSurface(
                  sdk: widget.dependencies.sdk,
                  resolver: _resolver!,
                  visitId: widget.dependencies.visitId,
                  persistenceProbe: widget.dependencies.persistenceProbe,
                  exportProbe: widget.dependencies.exportProbe,
                )
              : null,
        ),
      ),
    );
  }
}
