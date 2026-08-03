import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('context_required self-heal', () {
    test('stale_client_context_required_refreshes_resolves_resubmits_once_same_idempotency_key_and_succeeds', () async {
      const stableKey = 'heal-action-key-001';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(requestReference: 'req-first-ctx'),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-healed-success')),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit, idempotencyKeyFactory: () => stableKey);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
        interactionMode: InteractionMode.singleShot,
        idempotencyKeyFactory: () => stableKey,
      );

      final session = await heal.invoke(
        const CapabilityInvokeInput(
          capabilityId: 'clinic.visit_summary',
          capabilityVersion: '1.0.0',
          intent: 'summarise',
          context: {'patient_id': 'p-1'},
        ),
      );
      final terminal = await session.terminal;

      expect(terminal, isA<CompletedTerminal>());
      expect(refresh.refreshCallCount, 1);
      expect(resolver.resolveCalls, hasLength(1));
      expect(resolver.resolveCalls.single, [visitChiefComplaintV1Key]);
      expect(submit.submitCallCount, 2);
      expect(submit.idempotencyKeys, [stableKey, stableKey]);
      expect(sdk.lastRequestReference, 'req-healed-success');
    });

    test('second_context_required_stops_and_surfaces_request_reference', () async {
      const stableKey = 'heal-action-key-002';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(requestReference: 'req-heal-attempt-1'),
          contextRequiredErrorStep(requestReference: 'req-defect-surface'),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit, idempotencyKeyFactory: () => stableKey);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
        interactionMode: InteractionMode.singleShot,
        idempotencyKeyFactory: () => stableKey,
      );

      await expectLater(
        heal.invoke(
          const CapabilityInvokeInput(
            capabilityId: 'clinic.visit_summary',
            capabilityVersion: '1.0.0',
            intent: 'summarise',
            context: {'patient_id': 'p-1'},
          ),
        ),
        throwsA(
          isA<PlatformHttpException>()
              .having((e) => e.code, 'code', TaxonomyCode.contextRequired)
              .having((e) => e.requestReference, 'requestReference', 'req-defect-surface'),
        ),
      );

      expect(refresh.refreshCallCount, 1);
      expect(resolver.resolveCalls, hasLength(1));
      expect(submit.submitCallCount, 2);
      expect(sdk.lastRequestReference, 'req-defect-surface');
    });

    test('no_automatic_third_attempt_after_second_context_required', () async {
      const stableKey = 'heal-action-key-003';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(),
          contextRequiredErrorStep(requestReference: 'req-second-stop'),
          contextRequiredErrorStep(requestReference: 'req-would-be-third'),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit, idempotencyKeyFactory: () => stableKey);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
        interactionMode: InteractionMode.singleShot,
        idempotencyKeyFactory: () => stableKey,
      );

      await expectLater(
        heal.invoke(
          const CapabilityInvokeInput(
            capabilityId: 'clinic.visit_summary',
            capabilityVersion: '1.0.0',
            intent: 'summarise',
            context: {'patient_id': 'p-1'},
          ),
        ),
        throwsA(isA<PlatformHttpException>()),
      );

      expect(submit.submitCallCount, 2);
      expect(refresh.refreshCallCount, 1);
      expect(resolver.resolveCalls, hasLength(1));
    });

    test('conversational_capabilities_never_take_context_required_self_heal_path', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(script: [contextRequiredErrorStep(requestReference: 'req-conv-ctx')]);
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
        interactionMode: InteractionMode.conversational,
      );

      await expectLater(
        heal.invoke(conversationalInvokeInput()),
        throwsA(isA<PlatformHttpException>().having((e) => e.code, 'code', TaxonomyCode.contextRequired)),
      );

      expect(refresh.refreshCallCount, 0);
      expect(resolver.resolveCalls, isEmpty);
      expect(submit.submitCallCount, 1);
      expect(submit.idempotencyKeys, hasLength(1));
    });
  });
}
