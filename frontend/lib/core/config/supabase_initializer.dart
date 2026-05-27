import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';

/// Injectable wrapper around [SupabaseBootstrap] for testability.
///
/// Tests override [supabaseInitializerProvider] with a [FakeSupabaseInitializer]
/// instead of calling `SupabaseBootstrap.debugResetForTests()`.
class SupabaseInitializer {
  bool get isReady => SupabaseBootstrap.isReady;

  Future<void> initialize(SupabaseConfig config) => SupabaseBootstrap.ensureInitialized(config);
}

/// Test double that is always "ready" without touching the Supabase SDK.
class FakeSupabaseInitializer extends SupabaseInitializer {
  @override
  bool get isReady => true;

  @override
  Future<void> initialize(SupabaseConfig config) async {}
}

final supabaseInitializerProvider = Provider<SupabaseInitializer>((ref) {
  return SupabaseInitializer();
});
