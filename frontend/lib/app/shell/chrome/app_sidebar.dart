import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/state.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Responsive sidebar layout mode (B24 drives breakpoint → mode mapping).
enum AppSidebarMode {
  /// Full width with labels and org/branch header.
  expanded,

  /// Icon-only rail with tooltips.
  rail,

  /// Drawer overlay content — uses expanded layout; B24 supplies the drawer chrome.
  drawer,
}

/// Persistent clinic navigation sidebar with animated Signal active indicator.
class AppSidebar extends ConsumerStatefulWidget {
  const AppSidebar({
    this.mode = AppSidebarMode.expanded,
    this.organizationName,
    this.branchName,
    this.onToggleCollapsed,
    this.showCollapseToggle = true,
    super.key,
  });

  /// Current responsive mode.
  final AppSidebarMode mode;

  /// Organization overline in the header slot.
  final String? organizationName;

  /// Active branch title in the header slot.
  final String? branchName;

  /// Called when the collapse/expand control is pressed (expanded ↔ rail).
  final VoidCallback? onToggleCollapsed;

  /// Whether to show the collapse toggle in the header.
  final bool showCollapseToggle;

  static double widthFor(AppSidebarMode mode) {
    return switch (mode) {
      AppSidebarMode.rail => AppSpacing.s12 + AppSpacing.s2,
      AppSidebarMode.expanded || AppSidebarMode.drawer => AppSpacing.s12 * 5 + AppSpacing.s2,
    };
  }

  bool get _isCollapsed => mode == AppSidebarMode.rail;

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  final GlobalKey _navKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  final List<FocusNode> _focusNodes = [];
  List<ShellNavItem> _flatItems = const [];

  double _signalTop = 0;
  double _signalHeight = 0;
  bool _signalReady = false;

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateSignal());
    }
  }

  void _syncFocusNodes(int count) {
    while (_focusNodes.length < count) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
  }

  GlobalKey _keyFor(String itemId) => _itemKeys.putIfAbsent(itemId, GlobalKey.new);

  String _activeItemId(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return ShellNavConfig.itemIdForLocation(location) ?? ShellNavConfig.defaultItemId();
  }

  void _navigateTo(ShellNavItem item) {
    final route = ShellNavConfig.routeFor(item.id) ?? item.route;
    context.go(route);
  }

  void _updateSignal() {
    final activeId = _activeItemId(context);
    final itemKey = _itemKeys[activeId];
    final navContext = _navKey.currentContext;
    if (itemKey?.currentContext == null || navContext == null) {
      if (_signalReady) {
        setState(() => _signalReady = false);
      }
      return;
    }

    final itemBox = itemKey!.currentContext!.findRenderObject() as RenderBox?;
    final navBox = navContext.findRenderObject() as RenderBox?;
    if (itemBox == null || navBox == null || !itemBox.hasSize) {
      return;
    }

    final offset = itemBox.localToGlobal(Offset.zero, ancestor: navBox);
    final inset = AppSpacing.s1;
    final height = (itemBox.size.height - inset * 2).clamp(0.0, itemBox.size.height);

    setState(() {
      _signalTop = offset.dy + inset;
      _signalHeight = height;
      _signalReady = height > 0;
    });
  }

  KeyEventResult _handleNavKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _flatItems.isEmpty) {
      return KeyEventResult.ignored;
    }

    final currentIndex = _focusNodes.indexWhere((focus) => focus.hasFocus);
    if (currentIndex < 0) {
      return KeyEventResult.ignored;
    }

    int? nextIndex;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        nextIndex = (currentIndex + 1) % _flatItems.length;
      case LogicalKeyboardKey.arrowUp:
        nextIndex = (currentIndex - 1 + _flatItems.length) % _flatItems.length;
      case LogicalKeyboardKey.home:
        nextIndex = 0;
      case LogicalKeyboardKey.end:
        nextIndex = _flatItems.length - 1;
      default:
        return KeyEventResult.ignored;
    }

    _focusNodes[nextIndex].requestFocus();
    _navigateTo(_flatItems[nextIndex]);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final aiMode = ref.watch(aiModeProvider);
    final groups = ShellNavConfig.visibleGroups(ref);
    final footerItems = ShellNavConfig.visibleFooterItems(ref);
    final activeId = _activeItemId(context);
    final collapsed = widget._isCollapsed;
    final showLabels = !collapsed;

    _flatItems = [
      for (final group in groups) ...group.items,
      ...footerItems,
    ];
    _syncFocusNodes(_flatItems.length);

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSignal());

    final motion = AppMotion.resolvePreset(
      AppMotionPreset.nav,
      reduced: AppMotion.reduced(context),
    );
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Semantics(
      label: 'Main navigation',
      child: Container(
        width: AppSidebar.widthFor(widget.mode),
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: BorderDirectional(
            end: BorderSide(color: colors.borderSubtle),
          ),
        ),
        child: Column(
          children: [
            _SidebarHeader(
              collapsed: collapsed,
              density: density,
              organizationName: widget.organizationName,
              branchName: widget.branchName,
              showCollapseToggle: widget.showCollapseToggle && widget.onToggleCollapsed != null,
              onToggleCollapsed: widget.onToggleCollapsed,
            ),
            Expanded(
              child: Focus(
                onKeyEvent: _handleNavKey,
                child: Stack(
                  key: _navKey,
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: AppSpacing.s2,
                              vertical: AppSpacing.s3,
                            ),
                            children: [
                              for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) ...[
                                if (groups[groupIndex].label != null && showLabels)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: AppSpacing.s2,
                                      bottom: AppSpacing.s1,
                                    ),
                                    child: Text(
                                      groups[groupIndex].label!,
                                      style: typography.overline.copyWith(color: colors.textTertiary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                for (final item in groups[groupIndex].items)
                                  _buildNavItem(
                                    item: item,
                                    activeId: activeId,
                                    collapsed: collapsed,
                                    navItemHeight: density.navItemHeight,
                                    aiMode: aiMode,
                                  ),
                                if (groupIndex < groups.length - 1)
                                  const SizedBox(height: AppSpacing.s4),
                              ],
                            ],
                          ),
                        ),
                        if (footerItems.isNotEmpty)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: colors.borderSubtle),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: AppSpacing.s2,
                                vertical: AppSpacing.s3,
                              ),
                              child: Column(
                                children: [
                                  for (final item in footerItems)
                                    _buildNavItem(
                                      item: item,
                                      activeId: activeId,
                                      collapsed: collapsed,
                                      navItemHeight: density.navItemHeight,
                                      aiMode: aiMode,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_signalReady)
                      AnimatedPositioned(
                        duration: motion.duration,
                        curve: motion.curve,
                        top: _signalTop,
                        left: isRtl ? null : 0,
                        right: isRtl ? 0 : null,
                        height: _signalHeight,
                        width: AppSignal.thickness,
                        child: AppSignalLine(
                          orientation: AppSignalOrientation.vertical,
                          length: _signalHeight,
                          ai: aiMode,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required ShellNavItem item,
    required String activeId,
    required bool collapsed,
    required double navItemHeight,
    required bool aiMode,
  }) {
    final itemIndex = _flatItems.indexWhere((entry) => entry.id == item.id);
    final focusNode = itemIndex >= 0 ? _focusNodes[itemIndex] : FocusNode();

    return _NavItemButton(
      key: _keyFor(item.id),
      item: item,
      active: item.id == activeId,
      collapsed: collapsed,
      navItemHeight: navItemHeight,
      focusNode: focusNode,
      aiMode: aiMode,
      onTap: () => _navigateTo(item),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.density,
    required this.showCollapseToggle,
    this.organizationName,
    this.branchName,
    this.onToggleCollapsed,
  });

  final bool collapsed;
  final AppDensity density;
  final String? organizationName;
  final String? branchName;
  final bool showCollapseToggle;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      height: density.topbarHeight,
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: collapsed ? AppSpacing.s2 : AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          if (!collapsed && (organizationName != null || branchName != null))
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (organizationName != null)
                    Text(
                      organizationName!,
                      style: typography.overline.copyWith(color: colors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (branchName != null)
                    Text(
                      branchName!,
                      style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          if (showCollapseToggle)
            AppIconButton(
              icon: collapsed ? LucideIcons.panelLeft : LucideIcons.panelRight,
              semanticLabel: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
              size: AppIconButtonSize.sm,
              onPressed: onToggleCollapsed,
            ),
        ],
      ),
    );
  }
}

class _NavItemButton extends ConsumerWidget {
  const _NavItemButton({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.navItemHeight,
    required this.focusNode,
    required this.aiMode,
    required this.onTap,
    super.key,
  });

  final ShellNavItem item;
  final bool active;
  final bool collapsed;
  final double navItemHeight;
  final FocusNode focusNode;
  final bool aiMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final count = item.countProvider == null ? null : ref.watch(item.countProvider!);

    final button = AppPressable.builder(
      focusNode: focusNode,
      onTap: onTap,
      semanticLabel: item.label,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed);
        final background = active
            ? colors.surfaceSelected
            : hovered
            ? colors.surfaceHover
            : Colors.transparent;
        final foreground = active || hovered ? colors.textPrimary : colors.textSecondary;

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          height: navItemHeight,
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: collapsed ? 0 : AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.mdAll,
          ),
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              AppIcon(icon: item.icon, dimension: AppSpacing.s5, color: foreground),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Text(
                    item.label,
                    style: typography.body.copyWith(color: foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null && count > 0)
                  AppBadge(
                    variant: AppBadgeVariant.soft,
                    color: item.badgeColor,
                    size: AppBadgeSize.sm,
                    label: _formatCount(count),
                  ),
              ],
            ],
          ),
        );
      },
    );

    if (collapsed) {
      final badgeLabel = count != null && count > 0 ? ', $count' : '';
      return AppTooltip(
        message: '${item.label}$badgeLabel',
        side: AppTooltipSide.right,
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s0_5),
      child: button,
    );
  }

  static String _formatCount(int count) => count > 99 ? '99+' : '$count';
}
