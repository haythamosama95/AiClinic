import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav_handler.dart';
import 'package:ai_clinic/app/shell/layout/app_shell.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/providers/shell_chrome_provider.dart';
import 'package:ai_clinic/app/shell/providers/shell_sidebar_collapsed_provider.dart';
import 'package:ai_clinic/core/ui/components/app_command_bar.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/components/app_top_bar.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_scope.dart';

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
    final uri = GoRouterState.of(context).uri;
    final activeId = ShellNavConfig.itemIdForLocation(location) ?? '';
    final pageContext = ShellNavConfig.breadcrumbForLocation(
      location,
      uri: uri,
      onNavigate: (route) => context.go(route),
    );

    final auth = ref.watch(authSessionProvider);
    final setupLocked = auth.context?.needsClinicSetup ?? false;
    final chrome = ref.watch(shellChromeProvider);
    final collapsed = ref.watch(shellSidebarCollapsedProvider);

    final isDesignSystemPage = ShellNavConfig.isDesignSystemLocation(location);
    final designSystemFullWidth = ShellNavConfig.isDesignSystemFullWidth(uri);

    return CommandBarScope(
      enabled: !setupLocked,
      items: kDefaultCommandItems(
        onNavigate: setupLocked
            ? null
            : (itemId) {
                final route = ShellNavConfig.routeFor(itemId);
                if (route != null) {
                  context.go(route);
                }
              },
      ),
      child: ShellDevShellWrapper(
        child: AppShell(
          pageKey: location,
          fullWidth: isDesignSystemPage && designSystemFullWidth,
          fillViewport: isDesignSystemPage,
          sidebar: AppSidebar(
            items: ShellNavConfig.groups,
            footerItems: ShellNavConfig.footerItems(),
            activeId: activeId,
            collapsed: collapsed,
            org: chrome.orgName,
            branch: chrome.currentBranchName,
            onToggleCollapsed: () => ref.read(shellSidebarCollapsedProvider.notifier).toggle(),
            isItemEnabled: setupLocked ? (itemId) => ShellDevNavHandler.isActionItem(itemId) : null,
            onNavigate: (itemId) async {
              if (ShellDevNavHandler.isActionItem(itemId)) {
                await ShellDevNavHandler.handleItemSelection(context, ref, itemId);
                return;
              }

              if (setupLocked) {
                return;
              }

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
            shellActionsEnabled: !setupLocked,
            user: chrome.user,
            onSignOut: auth.isAuthenticated
                ? () async {
                    await ref.read(authSessionProvider.notifier).signOut();
                    if (context.mounted) {
                      context.go(AppRoutes.login);
                    }
                  }
                : null,
          ),
          child: ClinicSetupWelcomeScope(child: child),
        ),
      ),
    );
  }
}
