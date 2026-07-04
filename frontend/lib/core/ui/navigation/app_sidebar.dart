import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/navigation/nav_model.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/display/badge.dart';
import 'package:ai_clinic/core/ui/widgets/display/tooltip.dart';
import 'package:ai_clinic/core/ui/widgets/signal.dart';

/// Primary application sidebar with collapsible navigation groups.
class AppSidebar extends ConsumerStatefulWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.activeId,
    required this.onNavigate,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.org,
    required this.branch,
    this.footerItems = const [],
  });

  final List<NavGroup> items;
  final List<NavItem> footerItems;
  final String activeId;
  final ValueChanged<String> onNavigate;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final String org;
  final String branch;

  static const double expandedWidth = 248;
  static const double collapsedWidth = 56;

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  final _navFocusNode = FocusNode();
  final _itemFocusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    _navFocusNode.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  List<NavItem> get _allItems => [
    ...widget.items.expand((group) => group.items),
    ...widget.footerItems,
  ];

  FocusNode _focusNodeFor(String id) =>
      _itemFocusNodes.putIfAbsent(id, FocusNode.new);

  KeyEventResult _handleNavKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final items = _allItems;
    if (items.isEmpty) return KeyEventResult.ignored;

    String? focusedId;
    for (final entry in _itemFocusNodes.entries) {
      if (entry.value.hasFocus) {
        focusedId = entry.key;
        break;
      }
    }
    var currentIndex = focusedId == null
        ? -1
        : items.indexWhere((item) => item.id == focusedId);

    if (currentIndex < 0) return KeyEventResult.ignored;

    int? nextIndex;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        nextIndex = (currentIndex + 1) % items.length;
      case LogicalKeyboardKey.arrowUp:
        nextIndex = (currentIndex - 1 + items.length) % items.length;
      case LogicalKeyboardKey.home:
        nextIndex = 0;
      case LogicalKeyboardKey.end:
        nextIndex = items.length - 1;
      default:
        return KeyEventResult.ignored;
    }

    final nextItem = items[nextIndex];
    _focusNodeFor(nextItem.id).requestFocus();
    widget.onNavigate(nextItem.id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final topbarHeight = density.shellTopbarHeight;
    final navItemHeight = density.shellNavItemHeight;
    final collapsed = widget.collapsed;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final widthTransition = AppMotion.resolveTransition(
      preset: AppMotionPreset.collapse,
      reducedMotion: reducedMotion,
    );

    return Semantics(
      container: true,
      label: 'Main navigation',
      child: AnimatedContainer(
        duration: widthTransition.duration,
        curve: widthTransition.curve,
        width: collapsed ? AppSidebar.collapsedWidth : AppSidebar.expandedWidth,
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: BorderDirectional(
            end: BorderSide(color: colors.borderSubtle),
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: topbarHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: collapsed ? AppSpacing.s2 : AppSpacing.s3,
                    end: collapsed ? AppSpacing.s2 : AppSpacing.s3,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      if (!collapsed)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.org,
                                overflow: TextOverflow.ellipsis,
                                style: typography.overline.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                              Text(
                                widget.branch,
                                overflow: TextOverflow.ellipsis,
                                style: typography.bodyStrong.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      AppIconButton(
                        semanticLabel: collapsed
                            ? 'Expand sidebar'
                            : 'Collapse sidebar',
                        icon: _collapseIcon(collapsed, context.isRtl),
                        size: AppIconButtonSize.sm,
                        variant: AppIconButtonVariant.ghost,
                        onPressed: widget.onToggleCollapsed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _navFocusNode,
                onKeyEvent: _handleNavKey,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s3,
                  ),
                  children: [
                    for (final group in widget.items) ...[
                      if (group.label != null && !collapsed)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: AppSpacing.s2,
                            bottom: AppSpacing.s1,
                          ),
                          child: Text(
                            group.label!,
                            style: typography.overline.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      for (final item in group.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s0_5),
                          child: _SidebarNavItem(
                            item: item,
                            active: widget.activeId == item.id,
                            collapsed: collapsed,
                            height: navItemHeight,
                            focusNode: _focusNodeFor(item.id),
                            onNavigate: widget.onNavigate,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.s4),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.footerItems.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s3,
                  ),
                  child: Column(
                    children: [
                      for (final item in widget.footerItems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s0_5),
                          child: _SidebarNavItem(
                            item: item,
                            active: widget.activeId == item.id,
                            collapsed: collapsed,
                            height: navItemHeight,
                            focusNode: _focusNodeFor(item.id),
                            onNavigate: widget.onNavigate,
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
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.height,
    required this.focusNode,
    required this.onNavigate,
  });

  final NavItem item;
  final bool active;
  final bool collapsed;
  final double height;
  final FocusNode focusNode;
  final ValueChanged<String> onNavigate;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final active = widget.active;

    final background = active
        ? colors.surfaceSelected
        : _hovered
        ? colors.surfaceHover
        : Colors.transparent;
    final foreground = active || _hovered
        ? colors.textPrimary
        : colors.textSecondary;

    Widget button = Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onNavigate(widget.item.id);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onNavigate(widget.item.id),
            child: AnimatedContainer(
              duration: AppDurations.instant,
              curve: AppCurves.standard,
              height: widget.height,
              padding: EdgeInsetsDirectional.only(
                start: widget.collapsed ? 0 : AppSpacing.s2,
                end: widget.collapsed ? 0 : AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.mdAll,
                border: _focused
                    ? Border.all(color: colors.focusRing, width: 2)
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (active)
                    PositionedDirectional(
                      start: 0,
                      top: AppSpacing.s1,
                      bottom: AppSpacing.s1,
                      child: const SizedBox(
                        width: 2,
                        child: Signal(orientation: SignalOrientation.vertical),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: widget.collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      Icon(widget.item.icon, size: 20, color: foreground),
                      if (!widget.collapsed) ...[
                        const SizedBox(width: AppSpacing.s3),
                        Expanded(
                          child: Text(
                            widget.item.label,
                            overflow: TextOverflow.ellipsis,
                            style: typography.body.copyWith(color: foreground),
                          ),
                        ),
                        if (widget.item.count != null)
                          AppBadge(
                            size: AppBadgeSize.sm,
                            variant: AppBadgeVariant.neutral,
                            tone: AppBadgeTone.subtle,
                            label: '${widget.item.count}',
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.collapsed) {
      button = AppTooltip(
        message: Text(widget.item.label),
        placement: AppTooltipPlacement.right,
        child: button,
      );
    }

    return button;
  }
}

IconData _collapseIcon(bool collapsed, bool isRtl) {
  if (collapsed) {
    return isRtl ? Icons.chevron_left : Icons.chevron_right;
  }
  return isRtl ? Icons.chevron_right : Icons.chevron_left;
}
