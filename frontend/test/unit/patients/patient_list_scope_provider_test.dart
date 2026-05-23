import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientListScopeNotifier', () {
    test('defaults to thisBranch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(patientListScopeProvider), PatientListScope.thisBranch);
    });

    test('setScope updates in-memory value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(patientListScopeProvider.notifier).setScope(PatientListScope.allBranches);

      expect(container.read(patientListScopeProvider), PatientListScope.allBranches);
    });

    test('resets to thisBranch when user signs in', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(patientListScopeProvider.notifier).setScope(PatientListScope.allBranches);

      container.read(authSessionProvider.notifier).state = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(),
      );

      expect(container.read(patientListScopeProvider), PatientListScope.thisBranch);
    });

    test('resets to thisBranch on sign-out', () {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _FixedAuthSessionNotifier(
              AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(patientListScopeProvider.notifier).setScope(PatientListScope.allBranches);
      container.read(authSessionProvider.notifier).state = AuthSessionState(status: AuthSessionStatus.unauthenticated);

      expect(container.read(patientListScopeProvider), PatientListScope.thisBranch);
    });
  });
}

class _FixedAuthSessionNotifier extends AuthSessionNotifier {
  _FixedAuthSessionNotifier(this._initial);

  final AuthSessionState _initial;

  @override
  AuthSessionState build() => _initial;
}
