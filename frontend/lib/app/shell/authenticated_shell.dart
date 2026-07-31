import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav_handler.dart';
import 'package:ai_clinic/app/shell/layout/app_shell.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_presentation.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/app/shell/providers/shell_chrome_provider.dart';
import 'package:ai_clinic/app/shell/providers/shell_sidebar_collapsed_provider.dart';
import 'package:ai_clinic/core/ui/components/app_command_bar.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/components/app_top_bar.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_scope.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';

/// Authenticated route shell: sidebar, top bar, and feature content region.
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(permissionServiceProvider).canAccessAppointments()) {
      ref.watch(appointmentQueueShellWarmProvider);
      ref.watch(appointmentCalendarShellWarmProvider);
    }

    final routerState = GoRouterState.of(context);
    // Use the actual URI path so pushed routes (e.g. visit billing) get correct shell layout.
    final location = routerState.uri.path;
    final uri = routerState.uri;
    final activeId = ShellNavConfig.itemIdForLocation(location) ?? '';
    final isDesignSystemPage = ShellNavConfig.isDesignSystemLocation(location);
    syncBreadcrumbFromRoute(routerState, ref);
    final presentation = BreadcrumbPresentationConfig.forLocation(location);
    ref.watch(breadcrumbTrailProvider);

    final Widget? pageContext;
    if (presentation == BreadcrumbPresentation.shell) {
      pageContext = const BreadcrumbTrailView(mode: BreadcrumbViewMode.shell);
    } else if (presentation == BreadcrumbPresentation.none && isDesignSystemPage) {
      pageContext = ShellNavConfig.breadcrumbForLocation(
        location,
        uri: uri,
        onNavigate: (route) => context.go(route),
      );
    } else {
      pageContext = null;
    }

    final auth = ref.watch(authSessionProvider);
    // Default to locked when the session context is unknown (cold-start / loading)
    // so the shell chrome never renders interactive during the pre-auth window.
    final setupLocked = auth.context?.needsClinicSetup ?? true;
    final chrome = ref.watch(shellChromeProvider);
    final collapsed = ref.watch(shellSidebarCollapsedProvider);
    final queueCheckedInCount = ref.watch(appointmentQueueCheckedInCountProvider);
    final sidebarGroups = ShellNavConfig.groupsWithCounts(queueCheckedInCount: queueCheckedInCount);

    final designSystemFullWidth = ShellNavConfig.isDesignSystemFullWidth(uri);
    final fullWidth = ShellNavConfig.isFullWidthLocation(location) || (isDesignSystemPage && designSystemFullWidth);
    final fillViewport = isDesignSystemPage || ShellNavConfig.isFillViewportLocation(location);

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
          fullWidth: fullWidth,
          fillViewport: fillViewport,
          sidebar: AppSidebar(
            items: sidebarGroups,
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
