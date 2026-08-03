import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import 'boundary_session.dart';
import 'boundary_test_context.dart';
import 'fixture_factory.dart';

/// Cached staff credentials per role for the current clinic fixture.
class RoleSessions {
  RoleSessions(this.ctx, this.clinic);

  static const defaultPassword = 'TestPass1';

  final BoundaryTestContext ctx;
  final BoundaryClinicFixture clinic;

  final Map<StaffRole, ({String username, String password})> _cache = {};

  Future<({String username, String password})> credentials(StaffRole role) async {
    if (role == StaffRole.administrator) {
      return (username: 'admin', password: 'admin');
    }

    final existing = _cache[role];
    if (existing != null) {
      return existing;
    }

    final username = clinic.usernameFor(role);
    await ctx.auth.signOut();
    try {
      await ctx.auth.signIn(username: username, password: defaultPassword);
      await boundaryRefreshSessionForClinic(
        ctx.auth,
        clinic,
        username: username,
        password: defaultPassword,
      );
      final entry = (username: username, password: defaultPassword);
      _cache[role] = entry;
      await ctx.auth.signOut();
      return entry;
    } on AuthException {
      // Staff not provisioned yet for this clinic.
    } on StateError {
      // Session claims stale for this clinic after installation reset.
    }

    final created = await ctx.fixtures.createStaff(clinic: clinic, role: role, password: defaultPassword);
    final entry = (username: created.username, password: created.password);
    _cache[role] = entry;
    return entry;
  }

  Future<void> signInAs(StaffRole role) async {
    if (role == StaffRole.administrator) {
      await ctx.signInAdminForClinic(clinic);
      return;
    }

    final creds = await credentials(role);
    await ctx.signInStaff(creds.username, creds.password);
    await boundaryRefreshSessionForClinic(
      ctx.auth,
      clinic,
      username: creds.username,
      password: creds.password,
    );
  }
}
