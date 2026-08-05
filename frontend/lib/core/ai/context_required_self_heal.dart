import 'dart:math';

import 'ai_client_sdk.dart';
import 'context_resolver.dart';

/// Capability interaction mode from the A14/H1 manifest declaration (§5.1 / §8.4).
enum InteractionMode {
  singleShot,
  conversational,
}

/// Injectable manifest-cache refresh + mode lookup (FR-003; FR-008).
///
/// Production wiring to C1 discovery revalidation is deferred to a later
/// integration slice — see plan Constraints / quickstart §2. Tests spy the
/// refresh call and supply declared [interactionModeFor] values.
abstract class ManifestRefreshPort {
  Future<void> refresh();

  /// Declared `interactionMode` for [capabilityId] from the cached manifest.
  InteractionMode interactionModeFor(String capabilityId);
}

/// Typed heal abort when E3 cannot resolve keys named by `context_required`.
class ContextHealResolveException implements Exception {
  const ContextHealResolveException({
    required this.failure,
    this.requestReference,
  });

  final ContextResolveFailure failure;
  final String? requestReference;

  @override
  String toString() =>
      'ContextHealResolveException(code: ${failure.code}, '
      'unknownKey: ${failure.unknownKey}, failedKey: ${failure.failedKey}, '
      'requestReference: $requestReference)';
}

/// §8.4 `context_required` self-healing orchestration sibling (J2).
///
/// Composes [AiClientSdk] transport, [ContextResolver], and [ManifestRefreshPort].
/// `single_shot` only (from the refreshed manifest): one refresh → resolve →
/// same-key resubmit; second `context_required` surfaces the request reference
/// with no third attempt.
///
/// Resubmission keeps the original [CapabilityInvokeInput.capabilityVersion]
/// (J1 overlap window). C2 `manifestVersion` / `manifestCapabilityId` on the
/// rejection are diagnostic only and are not applied to the resubmit.
class ContextRequiredSelfHeal {
  ContextRequiredSelfHeal({
    required AiClientSdk sdk,
    required ContextResolver resolver,
    required ManifestRefreshPort manifestRefreshPort,
    String Function()? idempotencyKeyFactory,
  })  : _sdk = sdk,
        _resolver = resolver,
        _manifestRefreshPort = manifestRefreshPort,
        _idempotencyKeyFactory =
            idempotencyKeyFactory ?? _defaultIdempotencyKey;

  final AiClientSdk _sdk;
  final ContextResolver _resolver;
  final ManifestRefreshPort _manifestRefreshPort;
  final String Function() _idempotencyKeyFactory;

  /// Submit with optional one-round `context_required` self-heal for `single_shot`.
  Future<AiInvokeSession> invoke(CapabilityInvokeInput input) async {
    // Heal owns the action's idempotency key (FR-005) — pin across both submits.
    final key = _idempotencyKeyFactory();

    if (_manifestRefreshPort.interactionModeFor(input.capabilityId) !=
        InteractionMode.singleShot) {
      return _sdk.invoke(input, idempotencyKey: key);
    }

    var currentInput = input;
    var healAttempts = 0;

    while (true) {
      try {
        return await _sdk.invoke(currentInput, idempotencyKey: key);
      } on PlatformHttpException catch (error) {
        if (error.code != TaxonomyCode.contextRequired) {
          rethrow;
        }
        if (healAttempts >= 1) {
          rethrow;
        }

        final missingKeys = error.missingKeys;
        if (missingKeys == null || missingKeys.isEmpty) {
          // Unhealable rejection — do not burn the single automatic attempt.
          rethrow;
        }

        healAttempts++;
        await _manifestRefreshPort.refresh();

        // FR-008: A14 declaration after refresh is the gate, not caller config.
        if (_manifestRefreshPort.interactionModeFor(input.capabilityId) !=
            InteractionMode.singleShot) {
          rethrow;
        }

        final resolved = await _resolver.resolve(missingKeys);
        if (resolved is ContextResolveFailure) {
          throw ContextHealResolveException(
            failure: resolved,
            requestReference: error.requestReference,
          );
        }

        currentInput = _mergeResolvedContext(
          currentInput,
          (resolved as ContextResolveSuccess).payload,
        );
        continue;
      }
    }
  }

  CapabilityInvokeInput _mergeResolvedContext(
    CapabilityInvokeInput input,
    Map<String, Object?> resolved,
  ) {
    final merged = Map<String, dynamic>.from(input.context);
    for (final entry in resolved.entries) {
      merged[entry.key] = entry.value;
    }
    return CapabilityInvokeInput(
      capabilityId: input.capabilityId,
      // Keep the caller's version — overlap window serves enriched context
      // against the still-serving capability version (§5.2 Evolution; J1).
      capabilityVersion: input.capabilityVersion,
      intent: input.intent,
      context: merged,
      conversationId: input.conversationId,
      turnOrdinal: input.turnOrdinal,
      transcript: input.transcript,
    );
  }

  static String _defaultIdempotencyKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
