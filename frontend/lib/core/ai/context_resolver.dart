import 'context_provider_port.dart';
import 'context_registration.dart';

sealed class ContextResolveResult {
  const ContextResolveResult();
}

class ContextResolveSuccess extends ContextResolveResult {
  const ContextResolveSuccess(this.payload);

  final Map<String, Object?> payload;
}

class ContextResolveFailure extends ContextResolveResult {
  const ContextResolveFailure({
    required this.code,
    required this.unknownKey,
  });

  final String code;
  final String unknownKey;
}

/// Generic context key → resolver registry (§4.1).
class ContextResolver {
  ContextResolver({required ContextProviderPort providerPort})
      : _providerPort = providerPort;

  final ContextProviderPort _providerPort;
  final Map<String, Map<String, Object?>> _cache = <String, Map<String, Object?>>{};
  var _disposed = false;

  /// Discards screen-scoped cache (Clarification Q1).
  void dispose() {
    _disposed = true;
    _cache.clear();
  }

  /// Resolves [keys] to an assembled payload or a typed unknown-key failure.
  Future<ContextResolveResult> resolve(List<String> keys) async {
    if (_disposed) {
      throw StateError('ContextResolver disposed');
    }

    if (keys.isEmpty) {
      return const ContextResolveSuccess(<String, Object?>{});
    }

    for (final key in keys) {
      if (!contextRegistration.containsKey(key)) {
        return ContextResolveFailure(code: 'unknown_context_key', unknownKey: key);
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
      final value = await resolver(_providerPort);
      final snapshot = Map<String, Object?>.from(value);
      _cache[key] = snapshot;
      payload[key] = snapshot;
    }

    return ContextResolveSuccess(payload);
  }
}
