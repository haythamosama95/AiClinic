import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/session_context_loader.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';

import 'fixture_factory.dart';

/// Whether JWT claims include the clinic org and active branch for boundary RPCs.
bool boundarySessionClaimsMatchClinic(Map<String, dynamic> claims, BoundaryClinicFixture clinic) {
  final orgId = claims['organization_id']?.toString();
  if (orgId != clinic.organizationId) {
    return false;
  }

  final branchIds = SessionContextLoader.parseBranchIdsFromClaim(claims['branch_ids']?.toString() ?? '');
  return branchIds.contains(clinic.branchId);
}

Map<String, dynamic> boundarySessionClaims(AuthRepositoryImpl auth) {
  final session = auth.currentSession;
  if (session == null) {
    return const {};
  }
  return decodeAccessTokenClaims(session.accessToken).claims;
}

/// Refreshes the session until JWT org/branch claims match [clinic].
///
/// When [username] and [password] are provided, re-authenticates between attempts
/// so a stale JWT from a prior installation reset cannot block claim convergence.
Future<void> boundaryRefreshSessionForClinic(
  AuthRepositoryImpl auth,
  BoundaryClinicFixture clinic, {
  int attempts = 15,
  String? username,
  String? password,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (auth.currentSession == null && username != null && password != null) {
      await auth.signIn(username: username, password: password);
    } else {
      try {
        await auth.refreshSession();
      } on AuthException {
        if (username == null || password == null) {
          rethrow;
        }
        await auth.signOut();
        await auth.signIn(username: username, password: password);
      }
    }

    if (boundarySessionClaimsMatchClinic(boundarySessionClaims(auth), clinic)) {
      return;
    }

    if (username != null && password != null && attempt < attempts - 1) {
      await auth.signOut();
      await auth.signIn(username: username, password: password);
    }

    if (attempt < attempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }

  throw StateError(
    'Session claims did not match clinic fixture '
    '(org=${clinic.organizationId}, branch=${clinic.branchId}).',
  );
}
