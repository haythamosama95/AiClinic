import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/startup_test_support.dart';

void main() {
  testWidgets('redirects protected navigation back to the safe startup experience', (tester) async {
    await pumpStartupApp(tester);
    await completeStartupBootstrap(tester);

    expect(find.text('AiClinic clinic-local startup'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Try a protected route'), 120);
    await tester.tap(find.text('Try a protected route'));
    await tester.pumpAndSettle();

    expect(find.text('Protected route blocked'), findsOneWidget);
    expect(find.textContaining('Protected route'), findsWidgets);

    await tester.tap(find.text('Return to startup'));
    await tester.pumpAndSettle();

    expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
    expect(find.text('Protected route blocked'), findsNothing);
  });

  testWidgets('blocks direct protected route entry without rendering the placeholder', (tester) async {
    await pumpStartupApp(tester);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.protectedPlaceholder);
    await tester.pumpAndSettle();

    expect(find.text('Protected route blocked'), findsOneWidget);
    expect(find.text('This route should never render before authentication.'), findsNothing);
  });
}
