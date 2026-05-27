import 'dart:async';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';

IdleTimeoutService _shortIdleService(void Function() onIdle) {
  return IdleTimeoutService(idleDuration: const Duration(milliseconds: 80), onIdleTimeout: onIdle);
}

class _LifecycleAuthRepository extends AuthRepositoryImpl {
  _LifecycleAuthRepository() : super(_FakeSupabaseClient());

  int signOutCalls = 0;
  int coldStartClearCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> clearPersistedSessionOnColdStart() async {
    coldStartClearCalls++;
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('session lifecycle integration', () {
    testWidgets('pointer down on app root resets idle timer before timeout', (tester) async {
      late IdleTimeoutService idle;
      var idleFired = false;

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          idleTimeoutServiceProvider.overrideWith((ref) {
            idle = _shortIdleService(() => idleFired = true);
            ref.onDispose(idle.dispose);
            return idle;
          }),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      idle.enable(resetTimer: true);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 60));

      expect(idleFired, isFalse);
      expect(container.read(authSessionProvider).isAuthenticated, isTrue);
    });

    testWidgets('idle timeout signs out and shows inactivity message on login', (tester) async {
      late _LifecycleAuthRepository repo;
      late IdleTimeoutService idle;

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(AuthSessionNotifier.new),
          authRepositoryProvider.overrideWith((ref) => repo = _LifecycleAuthRepository()),
          idleTimeoutServiceProvider.overrideWith((ref) {
            idle = _shortIdleService(() {
              unawaited(ref.read(authSessionProvider.notifier).signOutDueToInactivity());
            });
            ref.onDispose(idle.dispose);
            return idle;
          }),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(authSessionProvider.notifier).state = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(),
      );
      idle.enable(resetTimer: true);
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      expect(repo.signOutCalls, greaterThanOrEqualTo(1));
      expect(container.read(authSessionProvider).isAuthenticated, isFalse);
      expect(container.read(authSessionProvider).failureMessage, kIdleTimeoutSignOutMessage);

      container.read(appRouterProvider).go(AppRoutes.login);
      await tester.pumpAndSettle();

      expect(find.text(kIdleTimeoutSignOutMessage), findsOneWidget);
    });

    testWidgets('keyboard input resets idle timer', (tester) async {
      late IdleTimeoutService idle;
      var idleFired = false;

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          idleTimeoutServiceProvider.overrideWith((ref) {
            idle = _shortIdleService(() => idleFired = true);
            ref.onDispose(idle.dispose);
            return idle;
          }),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      idle.enable(resetTimer: true);

      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump(const Duration(milliseconds: 50));

      expect(idleFired, isFalse);
      expect(container.read(authSessionProvider).isAuthenticated, isTrue);
    });

    testWidgets('explicit sign out does not show session-ended message', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          authRepositoryProvider.overrideWith((ref) => _LifecycleAuthRepository()),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      await container.read(authSessionProvider.notifier).signOut();
      await tester.pumpAndSettle();

      expect(container.read(authSessionProvider).failureMessage, isNull);

      container.read(appRouterProvider).go(AppRoutes.login);
      await tester.pumpAndSettle();
      expect(find.text(kSessionEndedMessage), findsNothing);
      expect(find.text(kIdleTimeoutSignOutMessage), findsNothing);
    });

    testWidgets('authenticated user navigating home after idle lands on login', (tester) async {
      late IdleTimeoutService idle;

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(AuthSessionNotifier.new),
          authRepositoryProvider.overrideWith((ref) => _LifecycleAuthRepository()),
          idleTimeoutServiceProvider.overrideWith((ref) {
            idle = _shortIdleService(() {
              unawaited(ref.read(authSessionProvider.notifier).signOutDueToInactivity());
            });
            ref.onDispose(idle.dispose);
            return idle;
          }),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(authSessionProvider.notifier).state = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(),
      );
      idle.enable(resetTimer: true);
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
    });
  });
}
