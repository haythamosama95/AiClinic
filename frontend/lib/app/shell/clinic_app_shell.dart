import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/app/shell/shell_command_items.dart';
import 'package:ai_clinic/app/shell/shell_nav.dart';
import 'package:ai_clinic/app/shell/shell_preferences.dart';
import 'package:ai_clinic/core/ui/layout/app_shell.dart';
import 'package:ai_clinic/core/ui/navigation/breadcrumb.dart';
import 'package:ai_clinic/core/ui/navigation/app_sidebar.dart';
import 'package:ai_clinic/core/ui/navigation/app_top_bar.dart';
import 'package:ai_clinic/core/ui/navigation/command_bar.dart';
import 'package:ai_clinic/core/ui/navigation/nav_model.dart';
import 'package:ai_clinic/core/ui/providers/command_bar_provider.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';

/// Production application shell wrapping authenticated feature routes.
///
/// Mirrors web `App.tsx`: sidebar, top bar, command palette, and persisted chrome state.
class ClinicAppShell extends ConsumerWidget {
  const ClinicAppShell({required this.child, super.key});

  final Widget child;

  bool _isDark(WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Widget? _buildPageContext(
    BuildContext context,
    String location,
    String activeNavId,
  ) {
    if (activeNavId == 'dev') {
      return AppBreadcrumb(
        items: [
          BreadcrumbItem(
            label: 'Dev',
            onTap: () => context.go(shellRouteForNavId('dev')!),
          ),
          BreadcrumbItem(label: shellBreadcrumbLabelForLocation(location)),
        ],
      );
    }

    final navItem = allNavItems
        .where((item) => item.id == activeNavId)
        .firstOrNull;
    if (navItem == null) return null;

    return AppBreadcrumb(
      items: [BreadcrumbItem(label: navItem.label)],
    );
  }

  void _navigate(BuildContext context, String navId) {
    final route = shellRouteForNavId(navId);
    if (route != null) {
      context.go(route);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final activeNavId = shellActiveNavIdForLocation(location);
    final fullWidth = shellFullWidthForLocation(location);
    final preferences = ref.watch(shellPreferencesProvider);
    final localeState = ref.watch(appLocaleProvider);
    final commandOpen = ref.watch(commandBarProvider);
    final isDark = _isDark(ref);

    final branch = mockBranches.firstWhere(
      (item) => item.id == preferences.branchId,
      orElse: () => mockBranches.first,
    );

    return AppShell(
      fullWidth: fullWidth,
      sidebar: AppSidebar(
        items: clinicNavGroups,
        footerItems: clinicNavFooter,
        activeId: activeNavId,
        onNavigate: (navId) => _navigate(context, navId),
        collapsed: preferences.sidebarCollapsed,
        onToggleCollapsed: () =>
            ref.read(shellPreferencesProvider.notifier).toggleSidebarCollapsed(),
        org: mockOrg,
        branch: branch.name,
      ),
      topBar: AppTopBar(
        pageContext: _buildPageContext(context, location, activeNavId),
        branches: mockBranches,
        currentBranchId: preferences.branchId,
        onBranchChange: (branchId) =>
            ref.read(shellPreferencesProvider.notifier).setBranchId(branchId),
        user: mockUser,
        notificationCount: mockNotificationCount,
        isDark: isDark,
        onToggleTheme: () =>
            setAppThemeMode(ref, isDark ? ThemeMode.light : ThemeMode.dark),
        locale: localeState.locale,
        onLocaleChange: (locale) =>
            ref.read(appLocaleProvider.notifier).setLocale(locale),
        onCommandBarOpen: () =>
            ref.read(commandBarProvider.notifier).openCommandBar(),
      ),
      commandBar: AppCommandBar(
        open: commandOpen,
        onClose: () => ref.read(commandBarProvider.notifier).closeCommandBar(),
        items: buildDefaultShellCommandItems((navId) => _navigate(context, navId)),
      ),
      child: child,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
