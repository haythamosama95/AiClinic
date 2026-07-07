import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/app/shell/layout/app_shell.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/providers/shell_chrome_provider.dart';
import 'package:ai_clinic/app/shell/providers/shell_sidebar_collapsed_provider.dart';
import 'package:ai_clinic/core/ui/components/app_command_bar.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/components/app_top_bar.dart';
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
    final activeId = ShellNavConfig.itemIdForLocation(location) ?? '';
    final pageContext = ShellNavConfig.breadcrumbForLocation(location);

    final auth = ref.watch(authSessionProvider);
    final chrome = ref.watch(shellChromeProvider);
    final collapsed = ref.watch(shellSidebarCollapsedProvider);

    final isDesignSystemPage = ShellNavConfig.isDesignSystemLocation(location);

    return CommandBarScope(
      items: kDefaultCommandItems(
        onNavigate: (itemId) {
          final route = ShellNavConfig.routeFor(itemId);
          if (route != null) {
            context.go(route);
          }
        },
      ),
      child: ShellDevShellWrapper(
        child: AppShell(
          fullWidth: isDesignSystemPage,
          fillViewport: isDesignSystemPage,
          sidebar: AppSidebar(
            items: ShellNavConfig.groups,
            footerItems: ShellNavConfig.footerItems(),
            activeId: activeId,
            collapsed: collapsed,
            org: chrome.orgName,
            branch: chrome.currentBranchName,
            onToggleCollapsed: () => ref.read(shellSidebarCollapsedProvider.notifier).toggle(),
            onNavigate: (itemId) {
              final route = ShellNavConfig.routeFor(itemId);
              if (route != null) {
                context.go(route);
              }
            },
          ),
          topBar: AppTopBar(
            pageContext: pageContext,
            branches: chrome.branches,
            currentBranchId: chrome.currentBranchId,
            onBranchChange: (branchId) => ref.read(branchSelectionProvider.notifier).selectBranch(branchId),
            user: chrome.user,
            onSignOut: auth.isAuthenticated ? () => ref.read(authSessionProvider.notifier).signOut() : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
