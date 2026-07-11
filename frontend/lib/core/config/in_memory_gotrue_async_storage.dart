import 'package:supabase_flutter/supabase_flutter.dart';

/// In-process PKCE storage for headless tests and cold-start bootstrap (no plugins).
///
/// The canonical [const InMemoryGotrueAsyncStorage] shares one in-memory map for
/// Supabase bootstrap. Use [InMemoryGotrueAsyncStorage.isolated] in unit tests when
/// PKCE entries must not leak across cases.
class InMemoryGotrueAsyncStorage extends GotrueAsyncStorage {
  const InMemoryGotrueAsyncStorage() : _isolatedStore = null;

  factory InMemoryGotrueAsyncStorage.isolated() => InMemoryGotrueAsyncStorage._();

  InMemoryGotrueAsyncStorage._() : _isolatedStore = {};

  final Map<String, String>? _isolatedStore;

  Map<String, String> get _store {
    final isolated = _isolatedStore;
    if (isolated != null) {
      return isolated;
    }
    return _sharedStore;
  }

  static final Map<String, String> _sharedStore = {};

  /// Clears all PKCE entries for this storage instance (shared or isolated).
  void reset() => _store.clear();

  @override
  Future<String?> getItem({required String key}) async => _store[key];

  @override
  Future<void> removeItem({required String key}) async {
    _store.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _store[key] = value;
  }
}
