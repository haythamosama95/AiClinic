// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

/// Wraps a widget in [ProviderScope] + [MaterialApp.router] for widget tests.
///
/// Use [overrides] to inject fakes for providers the widget depends on.
Widget wrapWithProviders(Widget child, {List<Override> overrides = const [], GoRouter? router}) {
  if (router != null) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// Creates a minimal [GoRouter] that shows [child] at `/` for widget tests.
GoRouter testRouterFor(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => child)],
  );
}
