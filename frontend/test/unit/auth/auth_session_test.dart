import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthSessionContext.needsClinicSetup', () {
    test('is true when setupRequired is true', () {
      final context = sampleAuthSessionContext(setupRequired: true);

      expect(context.needsClinicSetup, isTrue);
    });

    test('is true when organizationId is null', () {
      final context = sampleAuthSessionContext().copyWith(organizationId: null);

      expect(context.needsClinicSetup, isTrue);
    });

    test('is true when organizationId is empty or whitespace', () {
      expect(sampleAuthSessionContext().copyWith(organizationId: '').needsClinicSetup, isTrue);
      expect(sampleAuthSessionContext().copyWith(organizationId: '   ').needsClinicSetup, isTrue);
    });

    test('is false when setup is complete with a valid organization', () {
      final context = sampleAuthSessionContext(setupRequired: false);

      expect(context.needsClinicSetup, isFalse);
      expect(context.hasProperClinicSetup, isTrue);
    });

    test('copyWith recomputes needsClinicSetup when inputs change', () {
      final original = sampleAuthSessionContext(setupRequired: false);
      final cleared = original.copyWith(organizationId: null);

      expect(original.needsClinicSetup, isFalse);
      expect(cleared.needsClinicSetup, isTrue);
    });
  });

  group('AuthSessionState.isAuthenticated invariant', () {
    // Pins the load-bearing invariant that `isAuthenticated == true` implies
    // `context != null`, relied on by AuthRouteGuard (review §4.1). If anyone
    // ever relaxes this, the null-safe route-guard derefs must be revisited.
    test('is false for unknown status with null context', () {
      expect(AuthSessionState.initial().isAuthenticated, isFalse);
    });

    test('is false for loading status with null context', () {
      const state = AuthSessionState(status: AuthSessionStatus.loading);
      expect(state.isAuthenticated, isFalse);
    });

    test('is false for unauthenticated status', () {
      const state = AuthSessionState(status: AuthSessionStatus.unauthenticated);
      expect(state.isAuthenticated, isFalse);
    });

    test('is true only when status is authenticated and context is non-null', () {
      final state = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: false),
      );
      expect(state.isAuthenticated, isTrue);
      expect(state.context, isNotNull);
    });

    test('is false when status is authenticated but context is null', () {
      const state = AuthSessionState(status: AuthSessionStatus.authenticated);
      expect(state.isAuthenticated, isFalse);
    });

    test('copyWith preserves the invariant when clearing context', () {
      final authed = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: false),
      );
      final cleared = authed.copyWith(clearContext: true);
      expect(cleared.isAuthenticated, isFalse);
    });
  });
}
