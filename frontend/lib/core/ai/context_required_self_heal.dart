import 'ai_client_sdk.dart';
import 'context_resolver.dart';

/// Capability interaction mode gate for §8.4 self-healing (single_shot only).
enum InteractionMode {
  singleShot,
  conversational,
}

/// Injectable manifest-cache refresh (FR-003; production wires to C1 discovery).
abstract class ManifestRefreshPort {
  Future<void> refresh();
}

/// §8.4 `context_required` self-healing orchestration sibling (J2).
///
/// Composes [AiClientSdk] transport, [ContextResolver], and [ManifestRefreshPort].
/// `single_shot` only: one refresh → resolve → same-key resubmit; second
/// `context_required` surfaces the request reference with no third attempt.
class ContextRequiredSelfHeal {
  ContextRequiredSelfHeal({
    required AiClientSdk sdk,
    required ContextResolver resolver,
    required ManifestRefreshPort manifestRefreshPort,
    required InteractionMode interactionMode,
    String Function()? idempotencyKeyFactory,
  })  : _sdk = sdk,
        _resolver = resolver,
        _manifestRefreshPort = manifestRefreshPort,
        _interactionMode = interactionMode;

  final AiClientSdk _sdk;
  final ContextResolver _resolver;
  final ManifestRefreshPort _manifestRefreshPort;
  final InteractionMode _interactionMode;

  /// Submit with optional one-round `context_required` self-heal for `single_shot`.
  Future<AiInvokeSession> invoke(CapabilityInvokeInput input) async {
    if (_interactionMode != InteractionMode.singleShot) {
      return _sdk.invoke(input);
    }

    var currentInput = input;
    var healAttempts = 0;

    while (true) {
      try {
        return await _sdk.invoke(currentInput);
      } on PlatformHttpException catch (error) {
        if (error.code != TaxonomyCode.contextRequired) {
          rethrow;
        }
        if (healAttempts >= 1) {
          rethrow;
        }

        healAttempts++;
        await _manifestRefreshPort.refresh();

        final missingKeys = error.missingKeys ?? const <String>[];
        final resolved = await _resolver.resolve(missingKeys);
        if (resolved is ContextResolveSuccess) {
          currentInput = _mergeResolvedContext(currentInput, resolved.payload);
        }

        // Resubmit once with the same idempotency key (caller configures _sdk factory).
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
      capabilityVersion: input.capabilityVersion,
      intent: input.intent,
      context: merged,
      conversationId: input.conversationId,
      turnOrdinal: input.turnOrdinal,
      transcript: input.transcript,
    );
  }
}
