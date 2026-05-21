import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignOutTrackingNotifier extends TestAuthSessionNotifier {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    setUnauthenticated();
  }
}

void main() {
  testWidgets('shows loading copy when context is null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );

    expect(find.textContaining('Loading session context'), findsOneWidget);
  });

  testWidgets('sign out button invokes session notifier', (tester) async {
    final notifier = _SignOutTrackingNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );

    (notifier..setAuthenticated());
    await tester.pump();

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(notifier.signOutCalls, 1);
  });
}
