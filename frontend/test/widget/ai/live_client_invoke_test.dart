// I3 live client invoke widget/integration suite (T1–T11).
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/supabase_aat_mint_port.dart';
import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:ai_clinic/features/ai/surface/provisional_prose_view.dart';
import 'package:ai_clinic/features/ai/surface/request_reference_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

final _fakeClient = _FakeSupabaseClient();

class _HarnessFixedConnectionSubmitPort implements HttpsSubmitPort {
  _HarnessFixedConnectionSubmitPort(this.connection);

  final SseConnection connection;

  @override
  Future<SseConnection> submit({required CapabilityInvokeInput input, required SubmitRequestHeaders headers}) async =>
      connection;
}

class _SpyDiscoveryClient extends DiscoveryClient {
  _SpyDiscoveryClient({this.nextAuthFailure}) : super(httpClient: _FakeHttpClient());

  int fetchCallCount = 0;
  DiscoveryAuthFailure? nextAuthFailure;

  @override
  Future<DiscoveryFetchResult> fetchCapabilities({
    required String platformBaseUrl,
    required String aat,
    String? ifNoneMatch,
  }) async {
    fetchCallCount++;
    final failure = nextAuthFailure;
    if (failure != null) {
      throw failure;
    }
    return DiscoveryFetchResult(
      manifests: [sampleActiveManifest()],
      etag: '"etag-1"',
      notModified: false,
    );
  }
}

class _FakeHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnsupportedError('No network in harness');
  }
}

class _FakeDiscoveryHttpClient extends http.BaseClient {
  _FakeDiscoveryHttpClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode, headers: {
      'content-type': 'application/json',
    });
  }
}

class LiveClientInvokeHarness {
  LiveClientInvokeHarness({
    AiAvailability? availability,
    bool reachable = true,
    List<SubmitScriptStep>? submitScript,
    FakeMintPort? mintPort,
    FakeSubmitPort? submitPort,
    DiscoveryClient? discoveryClient,
    Object? availabilityThrowOnRead,
  })  : availabilityReader = FakeAiAvailabilityReader(
          availability ?? const AiAvailability(enrolled: true, platformBaseUrl: testPlatformBaseUrl),
          throwOnRead: availabilityThrowOnRead,
        ),
        reachabilityPort = FakePlatformReachabilityPort(reachable: reachable),
        networkSpy = InMemoryPlatformNetworkSpy(),
        persistenceProbe = InMemoryAiPersistenceProbe(),
        exportProbe = InMemoryAiExportProbe(),
        mintPort = mintPort ?? FakeMintPort(),
        submitPort = submitPort ?? FakeSubmitPort(script: submitScript),
        discoveryClient = discoveryClient ?? _SpyDiscoveryClient() {
    contextProvider = HarnessContextProviderPort();
    _resolver = ContextResolver(providerPort: contextProvider);
  }

  late final FakeAiAvailabilityReader availabilityReader;
  late final FakePlatformReachabilityPort reachabilityPort;
  late final InMemoryPlatformNetworkSpy networkSpy;
  late final InMemoryAiPersistenceProbe persistenceProbe;
  late final InMemoryAiExportProbe exportProbe;
  late final FakeMintPort mintPort;
  late final FakeSubmitPort submitPort;
  late final DiscoveryClient discoveryClient;
  late final HarnessContextProviderPort contextProvider;
  late final ContextResolver _resolver;

  void dispose() => _resolver.dispose();

  Future<LiveVisitSummaryComposition> composeAsync({required SupabaseClient client}) {
    return composeLiveVisitSummaryHost(
      client: client,
      visitId: testVisitId,
      availabilityReader: availabilityReader,
      reachabilityPort: reachabilityPort,
      mintPortOverride: mintPort,
      submitPortOverride: submitPort,
      discoveryClientOverride: discoveryClient,
      networkSpy: networkSpy,
      persistenceProbe: persistenceProbe,
      exportProbe: exportProbe,
      contextProviderOverride: contextProvider,
    );
  }

  LiveVisitSummaryComposition composeSync({
    required SupabaseClient client,
    bool? autoInvoke,
    int? maxTransportAttempts,
    Duration Function(int attemptAfterFailure)? transportBackoff,
  }) {
    return buildLiveVisitSummaryComposition(
      client: client,
      visitId: testVisitId,
      availabilityReader: availabilityReader,
      reachabilityPort: reachabilityPort,
      mintPortOverride: mintPort,
      submitPortOverride: submitPort,
      discoveryClientOverride: discoveryClient,
      networkSpy: networkSpy,
      persistenceProbe: persistenceProbe,
      exportProbe: exportProbe,
      contextProviderOverride: contextProvider,
      autoInvoke: autoInvoke,
      maxTransportAttempts: maxTransportAttempts,
      transportBackoff: transportBackoff,
      platformBaseUrl: testPlatformBaseUrl,
    );
  }

  Future<void> pumpHost(WidgetTester tester, {SupabaseClient? client, LiveVisitSummaryComposition? composition}) async {
    final supabase = client ?? _fakeClient;
    final resolved = composition ?? composeSync(client: supabase);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(supabase)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LiveVisitSummaryHostWidget(visitId: testVisitId, composition: resolved),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpUntilLiveSurfaceReady(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byKey(kAiSurfaceSessionActiveKey).evaluate().isNotEmpty ||
        find.byKey(kAiProvisionalProseKey).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Live surface session did not become ready');
}

Future<void> runArchitectureGuardOnLiveHostComposition() async {
  final frontendRoot = Directory(File('pubspec.yaml').existsSync() ? '.' : 'frontend').absolute.path;
  for (final relative in ['lib/core/ai', 'lib/features/ai/presentation/pages']) {
    final result = await Process.run(
      'dart',
      ['run', 'tool/architecture_guard/architecture_guard.dart', relative],
      workingDirectory: frontendRoot,
      runInShell: true,
    );
    expect(result.exitCode, 0, reason: '$relative: ${result.stderr} ${result.stdout}');
  }
}

void main() {
  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  group('live client invoke', () {
    testWidgets('live_host_mints_aat_resolves_context_submits_https', (tester) async {
      final harness = LiveClientInvokeHarness(
        submitScript: [
          SubmitOpenStreamStep(streamingThenCompleted(provisionalText: 'draft', terminalText: 'done')),
        ],
      );
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(harness.mintPort.mintCallCount, greaterThan(0));
      expect(harness.submitPort.submitCallCount, greaterThan(0));
      expect(harness.submitPort.idempotencyKeys, isNotEmpty);
      expect(harness.submitPort.inputs.single.capabilityId, kFirstAiCapabilityId);
      // E3 resolution: required keys appear in the submit context payload (FR-002).
      expect(harness.submitPort.inputs.single.context.containsKey(visitChiefComplaintV1Key), isTrue);
      expect(find.byKey(kAiAffordanceKey), findsOneWidget);
    });

    testWidgets('live_host_consumes_sse_to_terminal_renders_provisional', (tester) async {
      final harness = LiveClientInvokeHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(provisionalText: 'Live provisional draft', terminalText: 'Terminal answer'),
          ),
        ],
      );
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(harness.persistenceProbe.provisionalVisibles, contains('Live provisional draft'));
      expect(find.text('Terminal answer'), findsOneWidget);
    });

    testWidgets('live_host_no_commit_control_before_completed', (tester) async {
      final connection = DelayedFakeSseConnection(accepted: const AcceptedEvent(requestReference: 'req-live-3'));
      addTearDown(connection.close);
      final harness = LiveClientInvokeHarness();
      addTearDown(harness.dispose);
      final composition = buildLiveVisitSummaryComposition(
        client: _fakeClient,
        visitId: testVisitId,
        availabilityReader: harness.availabilityReader,
        reachabilityPort: harness.reachabilityPort,
        mintPortOverride: harness.mintPort,
        submitPortOverride: _HarnessFixedConnectionSubmitPort(connection),
        networkSpy: harness.networkSpy,
        contextProviderOverride: harness.contextProvider,
        autoInvoke: true,
        platformBaseUrl: testPlatformBaseUrl,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(_fakeClient)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: LiveVisitSummaryHostWidget(visitId: testVisitId, composition: composition)),
          ),
        ),
      );
      await _pumpUntilLiveSurfaceReady(tester);
      connection.emitContent(
        const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'Still streaming'}),
      );
      await tester.pump();

      expect(find.byKey(kAiAcceptKey), findsNothing);
      expect(find.byKey(kAiDiscardKey), findsNothing);
    });

    testWidgets('live_host_failure_displays_request_reference', (tester) async {
      final harness = LiveClientInvokeHarness(
        submitScript: [
          SubmitOpenStreamStep(failedStream(code: TaxonomyCode.validationFailed, requestReference: 'req-live-4')),
        ],
      );
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(find.byKey(kAiRequestReferenceKey), findsOneWidget);
      expect(find.textContaining('req-live-4'), findsOneWidget);
    });

    testWidgets('live_host_uses_terminal_payload_not_chunk_assembly', (tester) async {
      final harness = LiveClientInvokeHarness(
        submitScript: [
          SubmitOpenStreamStep([
            const AcceptedEvent(requestReference: 'req-live-5'),
            const ContentChunkEvent(kind: 'text_delta', payload: {'text': 'WRONG assembled chunk'}),
            CompletedEvent(result: terminalProseResult('Authoritative terminal payload')),
          ]),
        ],
      );
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(find.text('Authoritative terminal payload'), findsOneWidget);
      expect(find.text('WRONG assembled chunk'), findsNothing);
    });

    testWidgets('degraded_non_enrolled_hides_affordances_no_worker_probe', (tester) async {
      final harness = LiveClientInvokeHarness(availability: AiAvailability.nonEnrolled);
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(harness.networkSpy.platformCallCount, 0);
      expect(harness.reachabilityPort.callCount, 0);
      expect(harness.mintPort.mintCallCount, 0);
      expect(harness.submitPort.submitCallCount, 0);
    });

    testWidgets('degraded_unreachable_renders_normal_state_banner', (tester) async {
      final harness = LiveClientInvokeHarness(reachable: false);
      addTearDown(harness.dispose);

      await harness.pumpHost(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedUnreachableKey), findsOneWidget);
      expect(find.text('Clinical workflows remain available.'), findsOneWidget);
    });

    test('spy_production_mint_and_submit_ports_composed_on_hub', () {
      final composition = buildLiveVisitSummaryComposition(client: _fakeClient, visitId: testVisitId);

      expect(composition.mintPort, isA<SupabaseAatMintPort>());
      expect(composition.submitPort, isA<PlatformHttpsSubmitPort>());
      expect(composition.mintPort, isNot(isA<FakeMintPort>()));
      expect(composition.submitPort, isNot(isA<FakeSubmitPort>()));
    });

    testWidgets('live_idempotency_key_stable_for_single_user_action', (tester) async {
      final harness = LiveClientInvokeHarness(
        submitScript: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-idem')),
        ],
      );
      addTearDown(harness.dispose);
      final composition = harness.composeSync(
        client: _fakeClient,
        autoInvoke: true,
        maxTransportAttempts: 3,
        transportBackoff: (_) => Duration.zero,
      );

      await harness.pumpHost(tester, composition: composition);

      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (harness.submitPort.submitCallCount >= 3) {
          break;
        }
      }

      expect(harness.submitPort.submitCallCount, greaterThanOrEqualTo(3));
      expect(harness.submitPort.idempotencyKeys.toSet().length, 1);
    });

    testWidgets('discovery_auth_failure_taxonomy_no_manifest_body', (tester) async {
      final discovery = _SpyDiscoveryClient(
        nextAuthFailure: const DiscoveryAuthFailure(
          code: TaxonomyCode.unauthenticated,
          responseBody: {
            'code': 'unauthenticated',
            'request_reference': 'req-disc',
            'trace_id': 't-1',
            // Must not be treated as a discovery success payload.
          },
        ),
      );
      final harness = LiveClientInvokeHarness(discoveryClient: discovery);
      addTearDown(harness.dispose);
      final composition = await harness.composeAsync(client: _fakeClient);

      await harness.pumpHost(tester, composition: composition);

      expect(discovery.fetchCallCount, greaterThan(0));
      expect(composition.discoveryFailureCode, TaxonomyCode.unauthenticated);
      expect(composition.discoveryFailureReference, 'req-disc');
      expect(find.textContaining('req-disc'), findsOneWidget);
      expect(find.textContaining('manifests'), findsNothing);
      expect(composition.dependencies.autoInvoke, isFalse);
    });

    testWidgets('discovery_auth_failure_installation_suspended_hides_ai', (tester) async {
      final discovery = _SpyDiscoveryClient(
        nextAuthFailure: const DiscoveryAuthFailure(
          code: TaxonomyCode.installationSuspended,
          responseBody: {
            'code': 'installation_suspended',
            'request_reference': 'req-sus',
            'trace_id': 'trace-sus',
          },
        ),
      );
      final harness = LiveClientInvokeHarness(discoveryClient: discovery);
      addTearDown(harness.dispose);
      final composition = await harness.composeAsync(client: _fakeClient);

      await harness.pumpHost(tester, composition: composition);

      expect(composition.discoveryFailureCode, TaxonomyCode.installationSuspended);
      expect(find.byKey(kAiDegradedInstallationSuspendedKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.textContaining('manifests'), findsNothing);
      expect(harness.submitPort.submitCallCount, 0);
    });

    test('discovery_auth_failure_installation_suspended_wire', () async {
      final client = DiscoveryClient(
        httpClient: _FakeDiscoveryHttpClient(
          statusCode: 403,
          body: jsonEncode({
            'code': 'installation_suspended',
            'request_reference': 'req-sus',
            'trace_id': 'trace-sus',
          }),
        ),
      );

      await expectLater(
        client.fetchCapabilities(platformBaseUrl: testPlatformBaseUrl, aat: 'token'),
        throwsA(
          isA<DiscoveryAuthFailure>()
              .having((e) => e.code, 'code', TaxonomyCode.installationSuspended)
              .having((e) => e.responseBody.containsKey('manifests'), 'no manifests', isFalse),
        ),
      );
    });

    test('live_host_contains_no_prompt_provider_or_model_identifiers', () async {
      await runArchitectureGuardOnLiveHostComposition();
    });
  });
}
