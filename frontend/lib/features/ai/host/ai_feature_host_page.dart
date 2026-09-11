import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';

import '../availability/ai_availability.dart';
import '../degraded/ai_degraded_mode.dart';
import '../degraded/ai_degraded_view.dart';
import '../surface/first_ai_feature_surface.dart';
import '../surface/usage_gauge.dart';

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
    required this.manifestRefreshPort,
    required this.visitId,
    this.requiredContextKeys = kFirstAiRequiredContextKeys,
    this.networkSpy,
    this.persistenceProbe,
    this.exportProbe,
    this.mintPort,
    this.usageSummaryClient,
    this.skipReachabilityProbe = false,
    this.autoInvoke = true,
  });

  final AiAvailabilityReader availabilityReader;
  final PlatformReachabilityPort reachabilityPort;
  final AiClientSdk sdk;
  final ContextProviderPort contextProvider;
  final ManifestRefreshPort manifestRefreshPort;
  final String visitId;
  final List<String> requiredContextKeys;
  final PlatformNetworkSpy? networkSpy;
  final AiPersistenceProbe? persistenceProbe;
  final AiExportProbe? exportProbe;
  final AatMintPort? mintPort;
  final UsageSummaryClient? usageSummaryClient;
  final bool skipReachabilityProbe;

  /// When false, [FirstAiFeatureSurface] stays idle until the caller triggers invoke.
  final bool autoInvoke;
}

/// Standalone host composing availability gate + surface (Clarification Q2).
class AiFeatureHostPage extends StatefulWidget {
  const AiFeatureHostPage({super.key, required this.dependencies, this.embedded = false});

  final AiFeatureHostDependencies dependencies;

  /// When true, omit [Scaffold]/[AppBar] so the host can sit inside the app shell.
  final bool embedded;

  @override
  State<AiFeatureHostPage> createState() => _AiFeatureHostPageState();
}

class _AiFeatureHostPageState extends State<AiFeatureHostPage> {
  AiDegradedMode _mode = AiDegradedMode.nonEnrolled;
  var _loading = true;
  ContextResolver? _resolver;
  bool _platformReachable = false;
  int? _creditsUsed;
  int? _creditBudget;

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

      final mode = resolveDegradedMode(availability: availability, platformReachable: reachable);

      int? creditsUsed;
      int? creditBudget;
      if (mode == AiDegradedMode.ready && baseUrl != null && baseUrl.isNotEmpty) {
        final summary = await _fetchUsageSummary(baseUrl);
        creditsUsed = summary?.creditsUsed;
        creditBudget = summary?.creditBudget;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _mode = mode;
        _platformReachable = reachable;
        _creditsUsed = creditsUsed;
        _creditBudget = creditBudget;
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

  UsageSummaryClient _resolveUsageSummaryClient() {
    final override = widget.dependencies.usageSummaryClient;
    if (override != null) {
      return override;
    }
    if (widget.dependencies.networkSpy != null) {
      return UsageSummaryClient(
        httpClient: MockClient((request) async {
          widget.dependencies.networkSpy?.recordPlatformCall(request.url.toString());
          if (request.url.path.endsWith('/v1/usage')) {
            return http.Response(
              jsonEncode({
                'current_period': {
                  'period': '2026-09',
                  'credits_used': 42,
                  'credit_budget': 10000,
                },
                'prior_periods': <Object>[],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
    }
    return UsageSummaryClient();
  }

  Future<UsageSummaryFetchResult?> _fetchUsageSummary(String platformBaseUrl) async {
    final mintPort = widget.dependencies.mintPort;
    final aat = mintPort != null
        ? await mintPort.mint()
        : (widget.dependencies.networkSpy != null ? 'widget-test-aat' : null);
    if (aat == null) {
      return null;
    }
    try {
      return await _resolveUsageSummaryClient().fetchUsage(
        platformBaseUrl: platformBaseUrl,
        aat: aat,
      );
    } on UsageSummaryAuthFailure {
      return null;
    } catch (e, st) {
      debugPrint('Usage summary fetch failed: $e\n$st');
      return null;
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

  Widget _body() {
    if (_loading) {
      return const Center(child: Text(key: Key('ai_host_loading'), 'Loading…'));
    }

    // Non-enrolled: hide AI chrome entirely (§4.2; A11) — no banner, no AI app bar.
    if (_mode == AiDegradedMode.nonEnrolled) {
      return const SizedBox.shrink();
    }

    final hideSurface = _hidesSurface(_mode);

    final showUsageGauge =
        _mode == AiDegradedMode.ready && _creditsUsed != null && _creditBudget != null;

    final degradedView = AiDegradedView(
      mode: _mode,
      onRetry: _mode == AiDegradedMode.providerUnavailable ? _onRetry : null,
      child: hideSurface
          ? const Text('Clinical workflows remain available.')
          : _resolver != null
          ? FirstAiFeatureSurface(
              sdk: widget.dependencies.sdk,
              resolver: _resolver!,
              manifestRefreshPort: widget.dependencies.manifestRefreshPort,
              visitId: widget.dependencies.visitId,
              requiredContextKeys: widget.dependencies.requiredContextKeys,
              persistenceProbe: widget.dependencies.persistenceProbe,
              exportProbe: widget.dependencies.exportProbe,
              onTerminalFailure: _onTerminalFailure,
              autoInvoke: widget.dependencies.autoInvoke,
            )
          : null,
    );

    final chrome = <Widget>[
      if (showUsageGauge) ...[
        UsageGauge(creditsUsed: _creditsUsed!, creditBudget: _creditBudget!),
        const SizedBox(height: 16),
      ],
      if (_mode == AiDegradedMode.unreachable) const UsageGaugeUnreachableMarker(),
    ];

    if (widget.embedded) {
      return Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...chrome,
            degradedView,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...chrome,
          Expanded(child: degradedView),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    if (widget.embedded) {
      return body;
    }
    if (_loading) {
      return Scaffold(body: body);
    }
    if (_mode == AiDegradedMode.nonEnrolled) {
      return Scaffold(body: const UsageGaugeGate());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AI Feature')),
      body: body,
    );
  }
}
