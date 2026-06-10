import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/pages/setup_page.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'setup_test_support.dart';

void main() {
  Future<ProviderContainer> pumpSetupPage(
    WidgetTester tester, {
    List<Override> overrides = const [],
    GoRouter? router,
    AuthSessionNotifier Function()? authNotifierFactory,
  }) async {
    await tester.binding.setSurfaceSize(setupSurfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appRouter =
        router ??
        GoRouter(
          initialLocation: AppRoutes.bootstrap,
          routes: [
            GoRoute(path: AppRoutes.bootstrap, builder: (_, _) => const SetupPage()),
            GoRoute(
              path: AppRoutes.home,
              builder: (_, _) => const Scaffold(body: Text('Home reached')),
            ),
          ],
        );

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(authNotifierFactory ?? SetupTestAuthSessionNotifier.new),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          routerConfig: appRouter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(SetupPage)));
    return container;
  }

  testWidgets('renders SetupModal on bootstrap route', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container);

    expect(find.byType(SetupPage), findsOneWidget);
    expect(find.byType(SetupModal), findsOneWidget);
    expect(find.text("Let's get you started"), findsOneWidget);
  });

  testWidgets('shows first sign-in password warning once for bootstrap admin', (tester) async {
    final container = await pumpSetupPage(tester, authNotifierFactory: BootstrapAdminAuthSessionNotifier.new);

    expect(find.text('Change the default password'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Continue to clinic setup'));
    await tester.pumpAndSettle();

    expect(find.text('Change the default password'), findsNothing);
    expect(container.read(setupNotifierProvider).hasShownPasswordWarning, isTrue);
  });

  testWidgets('does not show password warning for non-bootstrap admin', (tester) async {
    final container = await pumpSetupPage(tester);
    setAdministratorSession(container);
    await tester.pumpAndSettle();

    expect(find.text('Change the default password'), findsNothing);
  });

  testWidgets('does not show password warning after already shown', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container, hasShownPasswordWarning: true);
    await tester.pumpAndSettle();

    expect(find.text('Change the default password'), findsNothing);
  });

  testWidgets('navigates home when setup completes', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container, hasShownPasswordWarning: true);
    await tester.pumpAndSettle();

    container.read(setupNotifierProvider.notifier).markSetupComplete();
    await tester.pumpAndSettle();

    expect(find.text('Home reached'), findsOneWidget);
  });

  testWidgets('dev panel visible in debug mode below modal', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container, hasShownPasswordWarning: true);
    await tester.pumpAndSettle();

    expect(find.text('Fill dummy clinic'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Reset installation'), findsOneWidget);
    expect(find.text('DEV ONLY'), findsOneWidget);
  });

  testWidgets('setup page shows blurred shell backdrop', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container, hasShownPasswordWarning: true);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(SetupModal), findsOneWidget);
  });

  testWidgets('setup dev widgets render on SetupPage not in shell nav footer', (tester) async {
    final container = await pumpSetupPage(tester);
    setBootstrapAdminSession(container, hasShownPasswordWarning: true);
    await tester.pumpAndSettle();

    expect(find.text('DEV ONLY'), findsOneWidget);
    expect(find.text('Fill dummy clinic'), findsOneWidget);
  });
}
