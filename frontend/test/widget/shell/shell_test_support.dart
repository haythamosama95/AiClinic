import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_icon_button.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_group.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_tree_connector.dart';
import 'package:ai_clinic/app/shell/widgets/shell_content_panel.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const shellSurfaceSize = Size(1280, 900);

/// Pumps [child] inside the app theme shell at [size].
Future<void> pumpShellWidget(
  WidgetTester tester, {
  required Widget child,
  Size size = shellSurfaceSize,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, appChild) => ForuiAppScope(child: appChild ?? const SizedBox.shrink()),
      home: Scaffold(body: child),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> pumpShellNav(
  WidgetTester tester, {
  String selectedItemId = 'dashboard',
  Set<String> expandedGroupIds = const {'appointments'},
  void Function(String itemId)? onItemSelected,
  void Function(String groupId)? onGroupToggled,
  bool settle = true,
}) {
  return pumpShellWidget(
    tester,
    settle: settle,
    child: ShellNav(
      selectedItemId: selectedItemId,
      expandedGroupIds: expandedGroupIds,
      onItemSelected: onItemSelected ?? (_) {},
      onGroupToggled: onGroupToggled ?? (_) {},
    ),
  );
}

Future<void> pumpShellNavItemRow(
  WidgetTester tester, {
  String label = 'Dashboard',
  IconData icon = Icons.dashboard_outlined,
  bool isSelected = false,
  VoidCallback? onTap,
  int? badgeCount,
  ShellNavBadgeTone? badgeTone,
  Widget? trailing,
  bool? hovered,
  bool enablePointerEvents = true,
  double collapseT = 0,
  bool settle = true,
}) {
  return pumpShellWidget(
    tester,
    settle: settle,
    child: ShellNavMetrics(
      collapseT: collapseT,
      child: ShellNavItemRow(
        label: label,
        icon: icon,
        isSelected: isSelected,
        onTap: onTap ?? () {},
        badgeCount: badgeCount,
        badgeTone: badgeTone,
        trailing: trailing,
        hovered: hovered,
        enablePointerEvents: enablePointerEvents,
      ),
    ),
  );
}

GoRouter shellTestRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('Home content')),
          ),
          GoRoute(
            path: AppRoutes.appointmentsCalendar,
            builder: (_, _) => const Scaffold(body: Text('Calendar content')),
          ),
          GoRoute(
            path: AppRoutes.appointmentsBook,
            builder: (_, _) => const Scaffold(body: Text('Book content')),
          ),
          GoRoute(
            path: AppRoutes.appointmentsQueue,
            builder: (_, _) => const Scaffold(body: Text('Queue content')),
          ),
          GoRoute(
            path: AppRoutes.foundationDemo,
            builder: (_, _) => const Scaffold(body: Text('Theme showcase content')),
          ),
        ],
      ),
    ],
  );
}

Future<void> pumpAuthenticatedShell(
  WidgetTester tester, {
  String initialLocation = AppRoutes.home,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(shellSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      routerConfig: shellTestRouter(initialLocation: initialLocation),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder shellNavCollapseControl() => find.widgetWithText(ShellNavItemRow, 'Collapse');

Finder shellNavExpandControl() => find.widgetWithText(ShellNavItemRow, 'Expand');

AnimatedOpacity? findNavRowHighlightOpacity(WidgetTester tester) {
  final row = tester.widget<ShellNavItemRow>(find.byType(ShellNavItemRow).first);
  final element = find.byWidget(row).evaluate().first;
  return find
      .descendant(of: find.byWidget(row), matching: find.byType(AnimatedOpacity))
      .evaluate()
      .map((e) => e.widget)
      .whereType<AnimatedOpacity>()
      .firstOrNull;
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
