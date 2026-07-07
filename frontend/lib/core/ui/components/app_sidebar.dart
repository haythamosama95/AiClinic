import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/components/app_tooltip.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Primary app navigation sidebar (web `AppSidebar`).
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    required this.items,
    required this.activeId,
    required this.onNavigate,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.org,
    required this.branch,
    this.footerItems = const [],
    super.key,
  });

  final List<AppNavGroup> items;
  final List<AppNavItem> footerItems;
  final String activeId;
  final ValueChanged<String> onNavigate;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final String org;
  final String branch;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final _focusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node
        ..onKeyEvent = null
        ..dispose();
    }
    super.dispose();
  }

  List<String> get _navIds => [
        for (final group in widget.items) ...group.items.map((item) => item.id),
        ...widget.footerItems.map((item) => item.id),
      ];

  FocusNode _nodeFor(String id) {
    return _focusNodes.putIfAbsent(id, () {
      final node = FocusNode();
      node.onKeyEvent = (node, event) => _handleNavKey(id, event);
      return node;
    });
  }

  KeyEventResult _handleNavKey(String currentId, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ids = _navIds;
    final currentIndex = ids.indexOf(currentId);
    if (currentIndex < 0) return KeyEventResult.ignored;

    int? nextIndex;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      nextIndex = (currentIndex + 1) % ids.length;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      nextIndex = (currentIndex - 1 + ids.length) % ids.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextIndex = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextIndex = ids.length - 1;
    }

    if (nextIndex == null) return KeyEventResult.ignored;

    final nextId = ids[nextIndex];
    widget.onNavigate(nextId);
    _nodeFor(nextId).requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final width = widget.collapsed ? AppShellTokens.sidebarCollapsedWidth : AppShellTokens.sidebarExpandedWidth;

    return Semantics(
      label: 'Main navigation',
      container: true,
      child: Material(
        color: colors.surfaceDefault,
        child: AnimatedContainer(
          duration: AppShellTokens.collapseDuration,
          width: width,
          decoration: BoxDecoration(
            border: BorderDirectional(end: BorderSide(color: colors.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(
                org: widget.org,
                branch: widget.branch,
                collapsed: widget.collapsed,
                onToggleCollapsed: widget.onToggleCollapsed,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space3),
                  children: [
                    for (final group in widget.items) ...[
                      if (group.label != null && !widget.collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.space2,
                            0,
                            AppSpacing.space2,
                            AppSpacing.space1,
                          ),
                          child: Text(group.label!, style: AppTypography.overline(context)),
                        ),
                      for (final item in group.items)
                        _SidebarNavItem(
                          item: item,
                          active: widget.activeId == item.id,
                          collapsed: widget.collapsed,
                          focusNode: _nodeFor(item.id),
                          onNavigate: widget.onNavigate,
                        ),
                      const SizedBox(height: AppSpacing.space4),
                    ],
                  ],
                ),
              ),
              if (widget.footerItems.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space3),
                    child: Column(
                      children: [
                        for (final item in widget.footerItems)
                          _SidebarNavItem(
                            item: item,
                            active: widget.activeId == item.id,
                            collapsed: widget.collapsed,
                            focusNode: _nodeFor(item.id),
                            onNavigate: widget.onNavigate,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.org,
    required this.branch,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final String org;
  final String branch;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      height: AppShellTokens.topBarHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: collapsed ? AppSpacing.space2 : AppSpacing.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!collapsed)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(org, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.overline(context)),
                      Text(
                        branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyStrong(context),
                      ),
                    ],
                  ),
                ),
              AppIconButton(
                icon: Icon(
                  collapsed ? Icons.read_more_outlined : Icons.menu_open_outlined,
                  size: 16,
                ),
                label: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                size: AppIconButtonSize.sm,
                onPressed: onToggleCollapsed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.focusNode,
    required this.onNavigate,
  });

  static const _minExpandedRowWidth = AppSpacing.space1 + 20 + AppSpacing.space3;

  final AppNavItem item;
  final bool active;
  final bool collapsed;
  final FocusNode focusNode;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = active ? colors.textPrimary : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = collapsed ? 0.0 : AppSpacing.space2 * 2;
          final rowWidth = constraints.maxWidth - horizontalPadding;
          final iconOnly = collapsed || rowWidth < _minExpandedRowWidth;

          final button = Material(
            color: active ? colors.surfaceSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              onTap: () => onNavigate(item.id),
              borderRadius: BorderRadius.circular(AppRadius.md),
              hoverColor: colors.surfaceHover,
              child: SizedBox(
                height: AppShellTokens.navItemHeight,
                child: Stack(
                  children: [
                    if (active)
                      const PositionedDirectional(
                        start: 0,
                        top: 4,
                        bottom: 4,
                        child: AppSignal(orientation: Axis.vertical),
                      ),
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : AppSpacing.space2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (iconOnly)
                              Expanded(child: Center(child: Icon(item.icon, size: 20, color: foreground)))
                            else ...[
                              const SizedBox(width: AppSpacing.space1),
                              Icon(item.icon, size: 20, color: foreground),
                              const SizedBox(width: AppSpacing.space3),
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body(context).copyWith(color: foreground),
                                ),
                              ),
                              if (item.count != null)
                                AppBadge(
                                  label: '${item.count}',
                                  color: BadgeColor.neutral,
                                  variant: BadgeVariant.soft,
                                  size: BadgeSize.sm,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          final focused = Semantics(
            button: true,
            label: item.label,
            selected: active,
            child: Focus(focusNode: focusNode, child: button),
          );

          if (iconOnly) {
            return AppTooltip(message: item.label, side: TooltipSide.right, child: focused);
          }

          return focused;
        },
      ),
    );
  }
}
