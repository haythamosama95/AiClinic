// I4 live context_required self-heal widget/integration suite (T5–T8).
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:ai_clinic/features/ai/surface/request_reference_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

class _LiveSelfHealHarness {
  _LiveSelfHealHarness({
    required this.refreshPort,
    List<SubmitScriptStep>? submitScript,
  })  : mintPort = FakeMintPort(),
        submitPort = FakeSubmitPort(script: submitScript),
        resolver = ResolverSpy(providerPort: FakeContextProviderPort()) {
    sdk = AiClientSdk(mintPort: mintPort, submitPort: submitPort);
  }

  final ManifestRefreshPort refreshPort;
  final FakeMintPort mintPort;
  late final FakeSubmitPort submitPort;
  late final AiClientSdk sdk;
  final ResolverSpy resolver;

  Widget surface({bool autoInvoke = true}) => FirstAiFeatureSurface(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refreshPort,
        visitId: testVisitId,
        autoInvoke: autoInvoke,
      );

  Future<void> pumpSurface(WidgetTester tester, {bool autoInvoke = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: surface(autoInvoke: autoInvoke)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live_self_heal_refreshes_resolves_resubmits_once_same_key', () {
    testWidgets('live surface path heals once with same idempotency key', (tester) async {
      final refresh = FakeManifestRefreshPort();
      final harness = _LiveSelfHealHarness(
        refreshPort: refresh,
        submitScript: [
          contextRequiredErrorStep(requestReference: 'req-first-ctx'),
          SubmitOpenStreamStep(completedStream(
            requestReference: 'req-healed-success',
            result: const {'final content': {'text': 'Healed summary.'}},
          )),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(refresh.refreshCallCount, 1);
      expect(harness.resolver.resolveCalls, hasLength(2));
      expect(harness.submitPort.submitCallCount, 2);
      expect(harness.submitPort.idempotencyKeys.length, 2);
      expect(
        harness.submitPort.idempotencyKeys.first,
        harness.submitPort.idempotencyKeys.last,
      );
      expect(find.byKey(kAiTerminalProseKey), findsOneWidget);
    });
  });

  group('live_self_heal_second_context_required_surfaces_reference', () {
    testWidgets('second context_required surfaces request reference', (tester) async {
      final refresh = FakeManifestRefreshPort();
      final harness = _LiveSelfHealHarness(
        refreshPort: refresh,
        submitScript: [
          contextRequiredErrorStep(requestReference: 'req-heal-attempt-1'),
          contextRequiredErrorStep(requestReference: 'req-defect-surface'),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(RequestReferenceView), findsOneWidget);
      expect(find.textContaining('req-defect-surface'), findsOneWidget);
      expect(refresh.refreshCallCount, 1);
      expect(harness.submitPort.submitCallCount, 2);
    });
  });

  group('live_self_heal_no_automatic_third_attempt', () {
    testWidgets('no automatic third attempt after second context_required', (tester) async {
      final refresh = FakeManifestRefreshPort();
      final harness = _LiveSelfHealHarness(
        refreshPort: refresh,
        submitScript: [
          contextRequiredErrorStep(),
          contextRequiredErrorStep(requestReference: 'req-second-stop'),
          contextRequiredErrorStep(requestReference: 'req-would-be-third'),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(harness.submitPort.submitCallCount, 2);
      expect(refresh.refreshCallCount, 1);
      expect(harness.resolver.resolveCalls, hasLength(2));
    });
  });

  group('live_self_heal_conversational_never_takes_path', () {
    testWidgets('conversational capabilities never take self-heal path', (tester) async {
      final refresh = FakeManifestRefreshPort(
        modes: {kFirstAiCapabilityId: InteractionMode.conversational},
      );
      final harness = _LiveSelfHealHarness(
        refreshPort: refresh,
        submitScript: [
          contextRequiredErrorStep(requestReference: 'req-conv-ctx'),
        ],
      );

      await harness.pumpSurface(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(refresh.refreshCallCount, 0);
      expect(harness.resolver.resolveCalls, hasLength(1));
      expect(harness.submitPort.submitCallCount, 1);
      expect(find.byType(RequestReferenceView), findsOneWidget);
      expect(find.textContaining('req-conv-ctx'), findsOneWidget);
    });
  });
}
