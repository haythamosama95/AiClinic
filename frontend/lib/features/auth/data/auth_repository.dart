import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';

/// Wraps Supabase Auth for staff sign-in lifecycle (no cross-restart persistence).
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Refreshes the JWT so custom claims reflect post-bootstrap org/branch state.
  Future<void> refreshSession() async {
    final response = await _client.auth.refreshSession();
    if (response.session == null) {
      throw const AuthException('Session refresh failed.');
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
