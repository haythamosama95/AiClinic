import 'context_provider_port.dart';
import 'context_registration.dart';

sealed class ContextResolveResult {
  const ContextResolveResult();
}

class ContextResolveSuccess extends ContextResolveResult {
  const ContextResolveSuccess(this.payload);

  final Map<String, Object?> payload;
}

/// Typed Resolver failure. Closed failure codes for this slice:
/// - `unknown_context_key` — [unknownKey] set
/// - `resolution_failed` — [failedKey] set (registered key whose port threw)
class ContextResolveFailure extends ContextResolveResult {
  const ContextResolveFailure({
    required this.code,
    this.unknownKey,
    this.failedKey,
  });

  final String code;

  /// Set when [code] is `unknown_context_key`.
  final String? unknownKey;

  /// Set when [code] is `resolution_failed`.
  final String? failedKey;
}

/// Generic context key → resolver registry (§4.1).
class ContextResolver {
  ContextResolver({required ContextProviderPort providerPort})
      : _providerPort = providerPort;

  final ContextProviderPort _providerPort;
  final Map<String, Map<String, Object?>> _cache = <String, Map<String, Object?>>{};
  var _disposed = false;

  /// Discards screen-scoped cache (Clarification Q1). Idempotent.
  void dispose() {
    _disposed = true;
    _cache.clear();
  }

  /// Resolves [keys] to an assembled payload or a typed failure.
  Future<ContextResolveResult> resolve(List<String> keys) async {
    if (_disposed) {
      throw StateError('ContextResolver disposed');
    }

    if (keys.isEmpty) {
      return const ContextResolveSuccess(<String, Object?>{});
    }

    for (final key in keys) {
      if (!contextRegistration.containsKey(key)) {
        return ContextResolveFailure(
          code: 'unknown_context_key',
          unknownKey: key,
        );
      }
    }

    final payload = <String, Object?>{};
    for (final key in keys) {
      final cached = _cache[key];
      if (cached != null) {
        payload[key] = Map<String, Object?>.from(cached);
        continue;
      }

      final resolver = contextRegistration[key]!;
      try {
        final value = await resolver(_providerPort);
        final snapshot = Map<String, Object?>.from(value);
        _cache[key] = snapshot;
        payload[key] = snapshot;
      } catch (_) {
        return ContextResolveFailure(
          code: 'resolution_failed',
          failedKey: key,
        );
      }
    }

    return ContextResolveSuccess(payload);
  }
}
