import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/presentation/placeholder_page.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/navigation/shell_route_meta.dart';

/// Builds a shell placeholder page for the current route (web `placeholderRoute`).
Widget shellPlaceholderPage(BuildContext context, GoRouterState state) {
  final itemId = ShellNavConfig.itemIdForLocation(state.matchedLocation) ?? 'home';

  return PlaceholderPage(
    key: ValueKey(state.matchedLocation),
    title: ShellRouteMeta.titleFor(itemId),
    description: ShellRouteMeta.descriptionFor(itemId),
  );
}

/// Phase 1 placeholder for [AppRoutes.clinicManagement]; swapped in Phase 2.
Widget clinicManagementPlaceholderPage(BuildContext context, GoRouterState state) {
  return shellPlaceholderPage(context, state);
}
