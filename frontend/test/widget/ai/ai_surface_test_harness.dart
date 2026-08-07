// Reusable pump helpers and spies for E4 AI feature surface widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:ai_clinic/features/ai/surface/provisional_prose_view.dart';
import 'package:ai_clinic/features/ai/surface/request_reference_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';

const testVisitId = '550e8400-e29b-41d4-a716-446655440000';
const testPlatformBaseUrl = 'https://ai.example.workers.dev';

class FakeAiAvailabilityReader implements AiAvailabilityReader {
  FakeAiAvailabilityReader(this._availability, {this.throwOnRead});

  AiAvailability _availability;
  final Object? throwOnRead;
  int readCallCount = 0;

  void setAvailability(AiAvailability availability) => _availability = availability;

  @override
  Future<AiAvailability> read() async {
    readCallCount++;
    final error = throwOnRead;
    if (error != null) {
      throw error;
    }
    return _availability;
  }
}

class FakePlatformReachabilityPort implements PlatformReachabilityPort {
  FakePlatformReachabilityPort({this.reachable = true});

  bool reachable;
  int callCount = 0;

  @override
  Future<bool> isReachable(String platformBaseUrl) async {
    callCount++;
    return reachable;
  }
}

class HarnessContextProviderPort implements ContextProviderPort {
  HarnessContextProviderPort({Map<String, Object?>? chiefComplaintPayload})
    : _payload = chiefComplaintPayload ?? const {'visit_id': testVisitId, 'complaint': 'Headache for two days.'};

  final Map<String, Object?> _payload;

  @override
  Future<Map<String, Object?>> fetchVisitChiefComplaint() async => Map<String, Object?>.from(_payload);
}

class AiSurfaceHarness {
  AiSurfaceHarness({
    AiAvailability? availability,
    bool reachable = true,
    List<SubmitScriptStep>? submitScript,
    this.skipReachabilityProbe = false,
    Object? availabilityThrowOnRead,
  }) : availabilityReader = FakeAiAvailabilityReader(
         availability ?? const AiAvailability(enrolled: true, platformBaseUrl: testPlatformBaseUrl),
         throwOnRead: availabilityThrowOnRead,
       ),
       reachabilityPort = FakePlatformReachabilityPort(reachable: reachable),
       networkSpy = InMemoryPlatformNetworkSpy(),
       persistenceProbe = InMemoryAiPersistenceProbe(),
       exportProbe = InMemoryAiExportProbe(),
       mintPort = FakeMintPort(),
       submitPort = FakeSubmitPort(script: submitScript),
       contextProvider = HarnessContextProviderPort(),
       manifestRefreshPort = FakeManifestRefreshPort() {
    sdk = AiClientSdk(mintPort: mintPort, submitPort: submitPort);
  }

  late final FakeManifestRefreshPort manifestRefreshPort;

  late final FakeAiAvailabilityReader availabilityReader;
  late final FakePlatformReachabilityPort reachabilityPort;
  late final InMemoryPlatformNetworkSpy networkSpy;
  late final InMemoryAiPersistenceProbe persistenceProbe;
  late final InMemoryAiExportProbe exportProbe;
  late final FakeMintPort mintPort;
  late final FakeSubmitPort submitPort;
  late AiClientSdk sdk;
  late final HarnessContextProviderPort contextProvider;
  final bool skipReachabilityProbe;
  final List<ContextResolver> _resolvers = [];

  ContextResolver createResolver() {
    final resolver = ContextResolver(providerPort: contextProvider);
    _resolvers.add(resolver);
    return resolver;
  }

  void disposeResolvers() {
    for (final resolver in _resolvers) {
      resolver.dispose();
    }
    _resolvers.clear();
  }

  AiFeatureHostDependencies hostDependencies({bool skipReachabilityProbe = false}) {
    return AiFeatureHostDependencies(
      availabilityReader: availabilityReader,
      reachabilityPort: reachabilityPort,
      sdk: sdk,
      contextProvider: contextProvider,
      manifestRefreshPort: manifestRefreshPort,
      visitId: testVisitId,
      networkSpy: networkSpy,
      persistenceProbe: persistenceProbe,
      exportProbe: exportProbe,
      skipReachabilityProbe: skipReachabilityProbe || this.skipReachabilityProbe,
    );
  }

  Widget host() => AiFeatureHostPage(dependencies: hostDependencies());

  Widget surface({bool autoInvoke = true}) => FirstAiFeatureSurface(
    sdk: sdk,
    resolver: createResolver(),
    manifestRefreshPort: manifestRefreshPort,
    visitId: testVisitId,
    persistenceProbe: persistenceProbe,
    exportProbe: exportProbe,
    autoInvoke: autoInvoke,
  );

  Future<void> pumpWidgetWithTheme(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: child));
  }

  Future<void> pumpHost(WidgetTester tester) async {
    await pumpWidgetWithTheme(tester, host());
    await tester.pumpAndSettle();
  }

  Future<void> pumpSurface(WidgetTester tester, {bool autoInvoke = true}) async {
    await pumpWidgetWithTheme(tester, Scaffold(body: surface(autoInvoke: autoInvoke)));
    await tester.pump();
  }

  /// Advances until the surface has attached its session event listener.
  Future<void> pumpUntilSurfaceReady(WidgetTester tester, {int maxPumps = 40}) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.byKey(kAiSurfaceSessionActiveKey).evaluate().isNotEmpty ||
          find.byKey(kAiProvisionalProseKey).evaluate().isNotEmpty ||
          find.byKey(kAiTerminalProseKey).evaluate().isNotEmpty ||
          find.byKey(kAiRequestReferenceKey).evaluate().isNotEmpty ||
          find.byKey(kAiLocalFailureKey).evaluate().isNotEmpty) {
        return;
      }
    }
    fail(
      'Surface session did not become ready '
      '(loading=${find.byKey(kAiSurfaceLoadingKey).evaluate().length}, '
      'texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList()})',
    );
  }

  Future<void> pumpDegraded(WidgetTester tester, AiDegradedMode mode, {VoidCallback? onRetry}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AiDegradedView(
            mode: mode,
            onRetry: onRetry,
            child: const Text('Clinical workflows remain available.'),
          ),
        ),
      ),
    );
  }
}

Map<String, Object?> terminalProseResult(String text) => {
  'final content': {'text': text, 'authoritative': true},
};

List<SseEvent> streamingThenCompleted({
  required String provisionalText,
  required String terminalText,
  String requestReference = 'req-stream-1',
}) => [
  AcceptedEvent(requestReference: requestReference),
  ContentChunkEvent(kind: 'text_delta', payload: {'text': provisionalText, 'provisional': true}),
  CompletedEvent(result: terminalProseResult(terminalText)),
];

List<SseEvent> multiDeltaThenCompleted({
  required List<String> provisionalChunks,
  required String terminalText,
  String requestReference = 'req-multi',
}) => [
  AcceptedEvent(requestReference: requestReference),
  for (final chunk in provisionalChunks)
    ContentChunkEvent(kind: 'text_delta', payload: {'text': chunk, 'provisional': true}),
  CompletedEvent(result: terminalProseResult(terminalText)),
];

Future<void> runArchitectureGuardOnFeaturesAi() async {
  final frontendRoot = Directory(File('pubspec.yaml').existsSync() ? '.' : 'frontend').absolute.path;
  final result = await Process.run(
    'dart',
    [
      'run',
      'tool/architecture_guard/architecture_guard.dart',
      'lib/features/ai',
    ],
    workingDirectory: frontendRoot,
    runInShell: true,
  );
  expect(result.exitCode, 0, reason: '${result.stderr} ${result.stdout}');
}
