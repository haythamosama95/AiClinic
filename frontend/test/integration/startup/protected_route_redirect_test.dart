import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/startup_test_support.dart';

void main() {
  testWidgets('redirects protected navigation to login placeholder when startup is valid', (tester) async {
    await pumpStartupApp(tester);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.protectedPlaceholder);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
    expect(find.text('UI Pending Migration'), findsOneWidget);
    expect(find.text(AppRoutes.login), findsOneWidget);
  });

  testWidgets('blocks direct protected route entry without rendering protected placeholder content', (tester) async {
    await pumpStartupApp(tester);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.protectedPlaceholder);
    await tester.pumpAndSettle();

    expect(find.text('This route should never render before authentication.'), findsNothing);
    expect(find.text('UI Pending Migration'), findsOneWidget);
  });
}
