import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

void main() {
  testWidgets('invalid deployment profile keeps user off login', (tester) async {
    await pumpAuthApp(tester, profileError: const InvalidDeploymentProfileException('Profile missing'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with your clinic staff account'), findsNothing);
  });

  testWidgets('authenticated user can open foundation demo pre-auth route', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
    container.read(appRouterProvider).go(AppRoutes.foundationDemo);
    await tester.pumpAndSettle();

    expect(find.text('Shared foundations demo'), findsOneWidget);
  });
}
