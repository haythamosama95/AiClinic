import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
=======
>>>>>>> master

import '../../helpers/auth_test_support.dart';
import 'clinic_setup_welcome_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staffMemberA = '00000000-0000-4000-8000-000000000010';
  const staffMemberB = '00000000-0000-4000-8000-000000000020';

  group('ClinicSetupWelcomeScope child presence', () {
    testWidgets('renders its child unchanged in all session states', (tester) async {
      final auth = TestAuthSessionNotifier();

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      expect(find.byKey(scopeChildSentinelKey), findsOneWidget);

      auth.setLoading();
      await tester.pump();
      expect(find.byKey(scopeChildSentinelKey), findsOneWidget);

      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
      await pumpUntilWelcomeVisible(tester);
      expect(find.byKey(scopeChildSentinelKey), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
      expect(find.byKey(scopeChildSentinelKey), findsOneWidget);
    });
  });

  group('ClinicSetupWelcomeScope welcome dialog gating', () {
    testWidgets('does not show welcome while session is unknown', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setSession(const AuthSessionState(status: AuthSessionStatus.unknown));

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setSession(const AuthSessionState(status: AuthSessionStatus.unknown));
      await tester.pump();
>>>>>>> master
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);
    });

    testWidgets('does not show welcome while session is loading', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setLoading();

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setLoading();
      await tester.pump();
>>>>>>> master
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);
    });

    testWidgets('does not show welcome while session is unauthenticated', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setUnauthenticated();

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setUnauthenticated();
      await tester.pump();
>>>>>>> master
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);
    });

    testWidgets('does not show welcome when authenticated without clinic setup required', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: false);

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
>>>>>>> master
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);
    });

    testWidgets('shows welcome when authenticated with needsClinicSetup', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: true);

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
>>>>>>> master
      await pumpUntilWelcomeVisible(tester);

      expect(welcomeDialogTitleFinder(), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
    });

    testWidgets('does not show welcome on the first frame before session resolves', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setLoading();

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setLoading();
>>>>>>> master
      await tester.pump();

      expect(welcomeDialogTitleFinder(), findsNothing);
      expect(find.byKey(scopeChildSentinelKey), findsOneWidget);
      await drainPendingFrames(tester);
    });
  });

  group('ClinicSetupWelcomeScope once-per-staff latch', () {
    testWidgets('shows welcome only once per staffMemberId until latch reset', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: true);

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
>>>>>>> master
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      auth.setLoading();
      await tester.pump();
      auth.setAuthenticated(setupRequired: true);
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
=======
      await tester.pump(const Duration(milliseconds: 200));

      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.loading,
          context: sampleAuthSessionContext(setupRequired: false),
        ),
      );
      await tester.pump();
      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(welcomeDialogTitleFinder(), findsNothing);

      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
>>>>>>> master
    });

    testWidgets('shows welcome again for a different staffMemberId that needs setup', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
>>>>>>> master
      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: authContextWithStaff(staffMemberId: staffMemberA, setupRequired: true),
        ),
      );
<<<<<<< HEAD

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======
      await tester.pump();
>>>>>>> master
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);

      auth.setUnauthenticated();
      await tester.pump();
      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: authContextWithStaff(staffMemberId: staffMemberB, setupRequired: true),
        ),
      );
      await pumpUntilWelcomeVisible(tester);

      expect(welcomeDialogTitleFinder(), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
    });

    testWidgets('sign-out invalidates latch so welcome shows again on next sign-in', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
>>>>>>> master
      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: authContextWithStaff(staffMemberId: staffMemberA, setupRequired: true),
        ),
      );
<<<<<<< HEAD

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

=======
      await tester.pump();
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
>>>>>>> master
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
=======
>>>>>>> master
      await tester.pump(const Duration(milliseconds: 200));

      auth.setUnauthenticated();
      await tester.pump();
      await drainPendingFrames(tester);
      expect(welcomeDialogTitleFinder(), findsNothing);

      auth.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: authContextWithStaff(staffMemberId: staffMemberA, setupRequired: true),
        ),
      );
      await pumpUntilWelcomeVisible(tester);

      expect(welcomeDialogTitleFinder(), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
    });
  });

  group('ClinicSetupWelcomeScope flow guards', () {
    testWidgets('single-flight guard prevents concurrent welcome dialogs', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: true);

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
>>>>>>> master
      await pumpUntilWelcomeVisible(tester);

      expect(welcomeDialogTitleFinder(), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);

      await dismissActiveSetupWelcomeFlow(tester, auth);
      await drainPendingFrames(tester);
    });

    testWidgets('out-of-dialog setup completion during welcome does not throw or strand dialogs', (tester) async {
      final auth = TestAuthSessionNotifier();
<<<<<<< HEAD
      auth.setAuthenticated(setupRequired: true);

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
=======

      await pumpClinicSetupWelcomeScope(tester, auth: auth);
      auth.setAuthenticated(setupRequired: true);
      await tester.pump();
>>>>>>> master
      await pumpUntilWelcomeVisible(tester);
      expect(welcomeDialogTitleFinder(), findsOneWidget);

      auth.setAuthenticated(setupRequired: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await drainPendingFrames(tester);

      expect(welcomeDialogTitleFinder(), findsNothing);
      expect(find.text('Start exploring'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
