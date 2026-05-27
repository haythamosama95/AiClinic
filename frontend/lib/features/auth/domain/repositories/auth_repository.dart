import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstract auth operations for staff sign-in lifecycle.
abstract class AuthRepository {
  Stream<AuthState> get authStateChanges;
  Session? get currentSession;
  User? get currentUser;
  Future<void> signIn({required String username, required String password});
  Future<void> signOut();
  Future<void> clearPersistedSessionOnColdStart();
  Future<void> refreshSession();
}
