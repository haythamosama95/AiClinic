import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';

/// Wraps Supabase Auth for staff sign-in lifecycle (no cross-restart persistence).
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  User? get currentUser => _client.auth.currentUser;

  @override
  Future<void> signIn({required String username, required String password}) async {
    await _client.auth.signInWithPassword(email: normalizeStaffUsername(username), password: password);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Clears any auth session from client storage on cold start (FR-004).
  ///
  /// Safe to call when no session exists; used with [EmptyLocalStorage] so reopening
  /// the app never restores a prior workstation session.
  @override
  Future<void> clearPersistedSessionOnColdStart() async {
    try {
      await _client.auth.signOut();
    } on AuthException {
      // No active session to clear.
    }
  }

  /// Refreshes the JWT so custom claims reflect post-bootstrap org/branch state.
  @override
  Future<void> refreshSession() async {
    final response = await _client.auth.refreshSession();
    if (response.session == null) {
      throw const AuthException('Session refresh failed.');
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(supabaseClientProvider));
});
