import 'package:supabase_flutter/supabase_flutter.dart';

/// In-process PKCE storage for headless tests and cold-start bootstrap (no plugins).
class InMemoryGotrueAsyncStorage extends GotrueAsyncStorage {
  const InMemoryGotrueAsyncStorage();

  static final Map<String, String> _store = {};

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
