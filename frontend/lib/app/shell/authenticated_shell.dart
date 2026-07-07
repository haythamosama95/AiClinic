import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/app/shell/layout/app_shell.dart';
import 'package:ai_clinic/app/shell/navigation/app_sidebar.dart';
import 'package:ai_clinic/app/shell/navigation/app_top_bar.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_model.dart';
import 'package:ai_clinic/app/shell/providers/shell_sidebar_collapsed_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Authenticated route shell: sidebar, top bar, and feature content region.
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(permissionServiceProvider).canAccessAppointments()) {
      ref.watch(appointmentQueueShellWarmProvider);
    }

    final location = GoRouterState.of(context).matchedLocation;
    final activeId = ShellNavConfig.itemIdForLocation(location);
    final pageLabel = ShellNavConfig.pageTitleForLocation(location);

    final auth = ref.watch(authSessionProvider);
    final session = auth.context;
    final collapsed = ref.watch(shellSidebarCollapsedProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDarkTheme = themeMode == ThemeMode.dark;

    final branches =
        session?.branchIds
            .map((id) => ShellBranch(id: id, name: id, org: session.organizationId))
            .toList(growable: false) ??
        const <ShellBranch>[];

    final user = ShellUser(
      name: session?.staffProfile.fullName ?? 'Staff',
      role: session?.staffProfile.role.displayLabel,
    );

    final isDesignSystemPage = ShellNavConfig.isDesignSystemLocation(location);

    return ShellDevShellWrapper(
      child: AppShell(
        fullWidth: isDesignSystemPage,
        fillViewport: isDesignSystemPage,
        sidebar: AppSidebar(
          groups: ShellNavConfig.groups,
          footerItems: ShellNavConfig.footerItems(),
          activeId: activeId,
          collapsed: collapsed,
          org: session?.organizationId ?? 'Organization',
          branch: session?.activeBranchId ?? 'Branch',
          onToggleCollapsed: () => ref.read(shellSidebarCollapsedProvider.notifier).toggle(),
          onNavigate: (itemId) {
            final route = ShellNavConfig.routeFor(itemId);
            if (route != null) {
              context.go(route);
            }
          },
        ),
        topBar: AppTopBar(
          pageContext: pageLabel != null ? AppTopBarPageLabel(label: pageLabel) : null,
          branches: branches,
          currentBranchId: ref.watch(branchSelectionProvider) ?? session?.activeBranchId,
          onBranchChange: (branchId) => ref.read(branchSelectionProvider.notifier).selectBranch(branchId),
          user: user,
          isDarkTheme: isDarkTheme,
          onToggleTheme: () {
            setAppThemeMode(ref, isDarkTheme ? ThemeMode.light : ThemeMode.dark);
          },
          onSignOut: auth.isAuthenticated ? () => ref.read(authSessionProvider.notifier).signOut() : null,
        ),
        child: child,
      ),
    );
  }
}
