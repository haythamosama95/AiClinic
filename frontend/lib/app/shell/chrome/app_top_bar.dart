import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/chrome/app_branch_switcher.dart';
import 'package:ai_clinic/app/shell/chrome/app_user_menu.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/state.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Sticky authenticated shell top bar with breadcrumb, command trigger, and utilities.
class AppTopBar extends ConsumerStatefulWidget {
  const AppTopBar({
    this.pageContext,
    this.notificationCount = 0,
    this.onNotificationsTap,
    this.showBranchSwitcher = true,
    this.toolbarSlot,
    super.key,
  });

  /// Breadcrumb or page title slot (typically [AppBreadcrumb]).
  final Widget? pageContext;

  /// Unread notification count for the bell badge.
  final int notificationCount;

  /// Called when the notifications button is pressed.
  final VoidCallback? onNotificationsTap;

  /// Whether the branch switcher is shown (B24 hides below `md`).
  final bool showBranchSwitcher;

  /// Optional trailing toolbar controls before notifications.
  final Widget? toolbarSlot;

  @override
  ConsumerState<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends ConsumerState<AppTopBar> {
  late final FocusNode _commandTriggerFocusNode;

  @override
  void initState() {
    super.initState();
    _commandTriggerFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(commandBarProvider.notifier).registerTrigger(_commandTriggerFocusNode);
    });
  }

  @override
  void dispose() {
    ref.read(commandBarProvider.notifier).registerTrigger(null);
    _commandTriggerFocusNode.dispose();
    super.dispose();
  }

  void _openCommandBar() {
    ref.read(commandBarProvider.notifier).openCommandBar();
  }

  void _toggleTheme() {
    final current = ref.read(themeModeProvider);
    final brightness = Theme.of(context).brightness;
    final next = switch (current) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    };
    setAppThemeMode(ref, next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final density = ref.watch(appDensityProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => Theme.of(context).brightness == Brightness.dark,
    };
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;

    return Semantics(
      header: true,
      child: Container(
        height: density.topbarHeight,
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border(
            bottom: BorderSide(color: colors.borderSubtle),
          ),
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (widget.pageContext != null)
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < AppBreakpoints.sm) {
                            return const SizedBox.shrink();
                          }
                          return widget.pageContext!;
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s2),
              child: _CommandTriggerButton(
                focusNode: _commandTriggerFocusNode,
                density: density,
                showShortcut: MediaQuery.sizeOf(context).width >= AppBreakpoints.sm,
                shortcutKeys: [isMac ? '⌘' : 'Ctrl', 'K'],
                onTap: _openCommandBar,
                onFocus: _openCommandBar,
              ),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.toolbarSlot != null) widget.toolbarSlot!,
                      if (widget.showBranchSwitcher) ...[
                        const AppBranchSwitcher(),
                        const SizedBox(width: AppSpacing.s2),
                      ],
                      _NotificationButton(
                        count: widget.notificationCount,
                        onTap: widget.onNotificationsTap,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      AppIconButton(
                        icon: isDark ? LucideIcons.sun : LucideIcons.moon,
                        semanticLabel: isDark ? 'Switch to light theme' : 'Switch to dark theme',
                        size: AppIconButtonSize.lg,
                        onPressed: _toggleTheme,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      const AppUserMenu(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandTriggerButton extends StatelessWidget {
  const _CommandTriggerButton({
    required this.focusNode,
    required this.density,
    required this.showShortcut,
    required this.shortcutKeys,
    required this.onTap,
    required this.onFocus,
  });

  final FocusNode focusNode;
  final AppDensity density;
  final bool showShortcut;
  final List<String> shortcutKeys;
  final VoidCallback onTap;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final verticalPadding = switch (density) {
      AppDensity.compact => AppSpacing.s1,
      AppDensity.standard => AppSpacing.s1 + AppSpacing.s0_5,
      AppDensity.comfortable => AppSpacing.s2,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: AppSpacing.s12 * 7,
        minWidth: AppSpacing.s12 * 3,
      ),
      child: AppPressable(
        focusNode: focusNode,
        onTap: onTap,
        semanticLabel: 'Open command bar',
        borderRadius: AppRadii.mdAll,
        child: Focus(
          onFocusChange: (focused) {
            if (focused) {
              onFocus();
            }
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s3,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              border: Border.all(color: colors.borderDefault),
              borderRadius: AppRadii.mdAll,
            ),
            child: Row(
              children: [
                AppIcon(
                  icon: LucideIcons.search,
                  dimension: AppSpacing.s4,
                  color: colors.iconMuted,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    'Search or jump to…',
                    style: typography.bodySm.copyWith(color: colors.textPlaceholder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showShortcut) ...[
                  const SizedBox(width: AppSpacing.s2),
                  AppKbd(keys: shortcutKeys),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.count,
    this.onTap,
  });

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final label = count > 0 ? 'Notifications, $count unread' : 'Notifications';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: LucideIcons.bell,
          semanticLabel: label,
          size: AppIconButtonSize.lg,
          onPressed: onTap,
        ),
        if (count > 0)
          PositionedDirectional(
            top: AppSpacing.s1 + AppSpacing.s0_5,
            end: AppSpacing.s1 + AppSpacing.s0_5,
            child: Semantics(
              label: '$count unread notifications',
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.s4,
                  minHeight: AppSpacing.s4,
                ),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s0_5),
                decoration: BoxDecoration(
                  color: colors.statusDangerFg,
                  borderRadius: AppRadii.fullAll,
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: typography.caption.copyWith(
                    color: colors.textInverse,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
