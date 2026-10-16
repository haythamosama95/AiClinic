import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('context_required self-heal', () {
    test('stale_client_context_required_refreshes_resolves_resubmits_once_same_idempotency_key_and_succeeds', () async {
      const stableKey = 'heal-action-key-001';
      var sdkFactoryCalls = 0;
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(requestReference: 'req-first-ctx'),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-healed-success')),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      // Default-style SDK factory would mint a *new* key per invoke — heal must pin.
      final sdk = AiClientSdk(
        mintPort: mint,
        submitPort: submit,
        idempotencyKeyFactory: () {
          sdkFactoryCalls++;
          return 'sdk-minted-$sdkFactoryCalls';
        },
      );
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
      expect(sdkFactoryCalls, 0, reason: 'heal must pin the key; SDK factory unused');
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
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
      expect(submit.idempotencyKeys, [stableKey, stableKey]);
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
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
      final refresh = FakeManifestRefreshPort(
        modes: {'clinic.chat_assistant': InteractionMode.conversational},
      );
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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

    test('context_resolve_failure_short_circuits_without_resubmit', () async {
      const stableKey = 'heal-action-key-resolve-fail';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(
            requestReference: 'req-stale-unknown-key',
            missingKeys: const ['unknown.stale_key@v1'],
          ),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-must-not-reach')),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
          isA<ContextHealResolveException>()
              .having((e) => e.failure.code, 'failure.code', 'unknown_context_key')
              .having((e) => e.failure.unknownKey, 'failure.unknownKey', 'unknown.stale_key@v1')
              .having((e) => e.requestReference, 'requestReference', 'req-stale-unknown-key'),
        ),
      );

      expect(refresh.refreshCallCount, 1);
      expect(resolver.resolveCalls, hasLength(1));
      expect(submit.submitCallCount, 1, reason: 'must not burn resubmit on resolve failure');
    });

    test('payload_less_context_required_rethrows_without_burning_heal_attempt', () async {
      const stableKey = 'heal-action-key-payload-less';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(
            requestReference: 'req-payload-less',
            nullMissingKeys: true,
          ),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-must-not-heal')),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
              .having((e) => e.requestReference, 'requestReference', 'req-payload-less')
              .having((e) => e.missingKeys, 'missingKeys', isNull),
        ),
      );

      expect(refresh.refreshCallCount, 0);
      expect(resolver.resolveCalls, isEmpty);
      expect(submit.submitCallCount, 1);
    });

    test('empty_missing_keys_context_required_rethrows_without_heal', () async {
      const stableKey = 'heal-action-key-empty-keys';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(
            requestReference: 'req-empty-keys',
            missingKeys: const [],
          ),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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

      expect(refresh.refreshCallCount, 0);
      expect(resolver.resolveCalls, isEmpty);
      expect(submit.submitCallCount, 1);
    });

    test('non_context_required_errors_passthrough_without_heal', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          SubmitHttpErrorStep(
            code: TaxonomyCode.quotaExhausted,
            requestReference: 'req-quota',
            retrySafe: false,
          ),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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
              .having((e) => e.code, 'code', TaxonomyCode.quotaExhausted)
              .having((e) => e.requestReference, 'requestReference', 'req-quota'),
        ),
      );

      expect(refresh.refreshCallCount, 0);
      expect(resolver.resolveCalls, isEmpty);
      expect(submit.submitCallCount, 1);
    });

    test('resubmit_keeps_original_capability_version_not_manifest_version', () async {
      const stableKey = 'heal-action-key-version';
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(
        script: [
          contextRequiredErrorStep(
            requestReference: 'req-versioned',
            manifestVersion: '2.0.0',
            manifestCapabilityId: 'clinic.visit_summary',
          ),
          SubmitOpenStreamStep(completedStream(requestReference: 'req-version-ok')),
        ],
      );
      final refresh = FakeManifestRefreshPort();
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
        idempotencyKeyFactory: () => stableKey,
      );

      await heal.invoke(
        const CapabilityInvokeInput(
          capabilityId: 'clinic.visit_summary',
          capabilityVersion: '1.0.0',
          intent: 'summarise',
          context: {'patient_id': 'p-1'},
        ),
      );

      expect(submit.inputs, hasLength(2));
      expect(submit.inputs[0].capabilityVersion, '1.0.0');
      expect(submit.inputs[1].capabilityVersion, '1.0.0');
      expect(submit.headerLog[1].capabilityVersion, '1.0.0');
    });

    test('manifest_declared_conversational_mode_blocks_heal_even_for_single_shot_shaped_input', () async {
      final mint = FakeMintPort();
      final submit = FakeSubmitPort(script: [contextRequiredErrorStep(requestReference: 'req-mode-gate')]);
      final refresh = FakeManifestRefreshPort(
        modes: {'clinic.visit_summary': InteractionMode.conversational},
      );
      final resolver = ResolverSpy(providerPort: FakeContextProviderPort());
      final sdk = AiClientSdk(mintPort: mint, submitPort: submit);
      final heal = ContextRequiredSelfHeal(
        sdk: sdk,
        resolver: resolver,
        manifestRefreshPort: refresh,
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

      expect(refresh.refreshCallCount, 0);
      expect(resolver.resolveCalls, isEmpty);
      expect(submit.submitCallCount, 1);
    });
  });
}
