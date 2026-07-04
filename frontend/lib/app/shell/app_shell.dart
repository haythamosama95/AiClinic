import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/app/shell/chrome/chrome.dart';
import 'package:ai_clinic/app/shell/command/command.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/state.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Authenticated app frame: sidebar, top bar, bounded content viewport, and overlays.
///
/// Mirrors the web [AppShell] composition — chrome at [AppBreakpoints] tiers,
/// global command bar + toast host, and ⌘K / Ctrl+K via [CommandBarShortcuts].
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  /// Feature route rendered in the shell content region.
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// User preference: `true` = icon rail, `false` = expanded labels.
  var _sidebarCollapsed = false;
  var _initializedCollapseDefault = false;

  static const _contentMaxWidth = AppSpacing.s12 * 24;

  void _toggleSidebarCollapsed() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  void _ensureCollapseDefault(double width) {
    if (_initializedCollapseDefault) {
      return;
    }
    _initializedCollapseDefault = true;
    _sidebarCollapsed = width >= AppBreakpoints.lg && width < AppBreakpoints.xl;
  }

  AppSidebarMode _inlineSidebarMode() {
    return _sidebarCollapsed ? AppSidebarMode.rail : AppSidebarMode.expanded;
  }

  Widget? _pageContext(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final itemId =
        ShellNavConfig.itemIdForLocation(location) ?? ShellNavConfig.defaultItemId();
    final label = ShellNavConfig.labelFor(itemId);
    if (label == null) {
      return null;
    }
    return AppBreadcrumb(items: [AppBreadcrumbItem(label: label)]);
  }

  String? _organizationName() {
    return ref.watch(clinicSetupOrganizationProvider).maybeWhen(
          data: (organization) => organization?.name,
          orElse: () => null,
        );
  }

  String? _branchName() {
    final currentBranchId = ref.watch(branchSelectionProvider);
    return ref.watch(staffAssignableBranchesProvider).maybeWhen(
          data: (branches) {
            if (branches.isEmpty) {
              return null;
            }
            return branches
                .firstWhere(
                  (branch) => branch.id == currentBranchId,
                  orElse: () => branches.first,
                )
                .name;
          },
          orElse: () => null,
        );
  }

  Future<void> _openNavDrawer({
    required String? organizationName,
    required String? branchName,
  }) {
    return showAppDrawer<void>(
      context,
      side: AppDrawerSide.inlineStart,
      size: AppDrawerSize.sm,
      semanticLabel: 'Main navigation',
      builder: (drawerContext, close) {
        return _ShellNavDrawerSidebar(
          onClose: () => close(),
          organizationName: organizationName,
          branchName: branchName,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final organizationName = _organizationName();
    final branchName = _branchName();

    return CommandBarShortcuts(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          _ensureCollapseDefault(width);

          final showInlineSidebar = width >= AppBreakpoints.lg;
          final showNavMenu = !showInlineSidebar;
          final sidebarMode = _inlineSidebarMode();
          final location = GoRouterState.of(context).matchedLocation;
          final isShowcaseRoute = location == AppRoutes.foundationDemo;
          final contentMaxWidth = isShowcaseRoute ? double.infinity : _contentMaxWidth;
          final contentPadding = isShowcaseRoute ? AppSpacing.s4 : AppSpacing.s6;

          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: colors.surfaceCanvas,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showInlineSidebar)
                      AppSidebar(
                        mode: sidebarMode,
                        organizationName: organizationName,
                        branchName: branchName,
                        showCollapseToggle: true,
                        onToggleCollapsed: _toggleSidebarCollapsed,
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTopBar(
                            pageContext: _pageContext(context),
                            showBranchSwitcher: width >= AppBreakpoints.md,
                            toolbarSlot: showNavMenu
                                ? Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: AppSpacing.s2,
                                    ),
                                    child: AppIconButton(
                                      icon: LucideIcons.menu,
                                      semanticLabel: 'Open navigation menu',
                                      size: AppIconButtonSize.lg,
                                      onPressed: () => _openNavDrawer(
                                        organizationName: organizationName,
                                        branchName: branchName,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: Semantics(
                              container: true,
                              label: 'Main content',
                              child: Material(
                                color: colors.surfaceCanvas,
                                child: Align(
                                  alignment: AlignmentDirectional.topCenter,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: contentMaxWidth,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsetsDirectional.all(
                                        contentPadding,
                                      ),
                                      child: widget.child,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const AppToastOverlayHost(),
              const AppCommandBar(),
            ],
          );
        },
      ),
    );
  }
}

/// Navigation drawer panel that dismisses when the active route changes.
class _ShellNavDrawerSidebar extends StatefulWidget {
  const _ShellNavDrawerSidebar({
    required this.onClose,
    this.organizationName,
    this.branchName,
  });

  final VoidCallback onClose;
  final String? organizationName;
  final String? branchName;

  @override
  State<_ShellNavDrawerSidebar> createState() => _ShellNavDrawerSidebarState();
}

class _ShellNavDrawerSidebarState extends State<_ShellNavDrawerSidebar> {
  late final GoRouterDelegate _routerDelegate;

  @override
  void initState() {
    super.initState();
    _routerDelegate = GoRouter.of(context).routerDelegate;
    _routerDelegate.addListener(_handleRouteChanged);
  }

  @override
  void dispose() {
    _routerDelegate.removeListener(_handleRouteChanged);
    super.dispose();
  }

  void _handleRouteChanged() {
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSidebar(
      mode: AppSidebarMode.drawer,
      organizationName: widget.organizationName,
      branchName: widget.branchName,
      showCollapseToggle: false,
    );
  }
}
