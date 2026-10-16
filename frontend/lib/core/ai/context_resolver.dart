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
  ///
  /// Thin wrapper over [resolveRequests] with empty/null arguments per key
  /// (backward-compatible E3 key-list API).
  Future<ContextResolveResult> resolve(List<String> keys) {
    return resolveRequests([
      for (final key in keys)
        <String, Object?>{
          'key': key,
          'arguments': null,
        },
    ]);
  }

  /// Resolves `{key, arguments}` request entries (§6.7.2 / H3 arguments channel).
  Future<ContextResolveResult> resolveRequests(
    List<Map<String, Object?>> requests,
  ) async {
    if (_disposed) {
      throw StateError('ContextResolver disposed');
    }

    if (requests.isEmpty) {
      return const ContextResolveSuccess(<String, Object?>{});
    }

    for (final request in requests) {
      final key = request['key'];
      if (key is! String || !contextRegistration.containsKey(key)) {
        return ContextResolveFailure(
          code: 'unknown_context_key',
          unknownKey: key is String ? key : '$key',
        );
      }
    }

    final payload = <String, Object?>{};
    for (final request in requests) {
      final key = request['key']! as String;
      final cached = _cache[key];
      if (cached != null) {
        payload[key] = Map<String, Object?>.from(cached);
        continue;
      }

      final resolver = contextRegistration[key]!;
      final arguments = _asArgumentsMap(request['arguments']);
      try {
        final value = await resolver(_providerPort, arguments);
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

  Map<String, Object?>? _asArgumentsMap(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Map<String, Object?>) {
      return Map<String, Object?>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
