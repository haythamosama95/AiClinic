// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

AuthSessionContext sampleAuthSessionContext({
  bool setupRequired = false,
  StaffRole role = StaffRole.owner,
  List<String> branchIds = const ['00000000-0000-4000-8000-000000000001'],
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
    activeBranchId: branchIds.isEmpty ? null : branchIds.first,
    permissions: const {'patients.read'},
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
}
