import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_host.dart';

void main() {
  testWidgets('ThemeTransitionHost mounts inside MaterialApp builder without errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => ThemeTransitionHost(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: Text('hello')),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('theme transition reaches root navigator overlay without throwing', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rootNavigatorKeyProvider.overrideWithValue(navigatorKey)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.light,
          builder: (context, child) => ThemeTransitionHost(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(tester.element(find.byType(ThemeTransitionHost)));
    final runner = container.read(themeTransitionRegistryProvider).runner;

    expect(runner, isNotNull);

    final transition = runner!(ThemeMode.dark, const Offset(100, 100));
    unawaited(transition);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await transition;
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme transition can run twice in a row', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rootNavigatorKeyProvider.overrideWithValue(navigatorKey)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.light,
          builder: (context, child) => ThemeTransitionHost(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final runner = ProviderScope.containerOf(
      tester.element(find.byType(ThemeTransitionHost)),
    ).read(themeTransitionRegistryProvider).runner!;

    for (final target in [ThemeMode.dark, ThemeMode.light]) {
      final transition = runner(target, const Offset(100, 100));
      unawaited(transition);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await transition;
      expect(tester.takeException(), isNull);
    }
  });
}
