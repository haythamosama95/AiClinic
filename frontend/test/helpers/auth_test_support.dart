// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

AuthSessionContext sampleAuthSessionContext({
  bool setupRequired = false,
  StaffRole role = StaffRole.owner,
  List<String> branchIds = const ['00000000-0000-4000-8000-000000000001'],
  String? activeBranchId,
  Set<String> permissions = const {'patients.view'},
}) {
  return AuthSessionContext(
    staffProfile: StaffProfile(
      staffMemberId: '00000000-0000-4000-8000-000000000010',
      fullName: 'Test Staff',
      role: role,
      isBootstrapAdmin: false,
      isActive: true,
    ),
    organizationId: setupRequired ? null : '00000000-0000-4000-8000-000000000020',
    branchIds: branchIds,
    activeBranchId: activeBranchId ?? (branchIds.isEmpty ? null : branchIds.first),
    permissions: permissions,
    setupRequired: setupRequired,
  );
}

/// Deterministic auth session for router and login tests.
class TestAuthSessionNotifier extends AuthSessionNotifier {
  @override
  AuthSessionState build() => _state;

  AuthSessionState _state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);

  void setSession(AuthSessionState state) {
    _state = state;
    this.state = state;
  }

  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: setupRequired),
      ),
    );
  }

  void setUnauthenticated({String? failureMessage}) {
    setSession(AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: failureMessage));
  }

  void setLoading() {
    setSession(const AuthSessionState(status: AuthSessionStatus.loading));
  }

  @override
  Future<void> ensureReadyForSignIn() async {}

  @override
  Future<void> syncAfterSignIn() async {}

  @override
  Future<void> refreshSessionContext() async {}

  @override
  Future<void> reloadContext() async {}

  @override
  Future<void> signOutDueToInactivity() async {
    setUnauthenticated(failureMessage: kIdleTimeoutSignOutMessage);
  }
}
