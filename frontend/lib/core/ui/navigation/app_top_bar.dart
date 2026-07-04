import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/navigation/branch_switcher.dart';
import 'package:ai_clinic/core/ui/navigation/nav_model.dart';
import 'package:ai_clinic/core/ui/navigation/user_menu.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/display/kbd.dart';

/// Sticky top chrome: page context, command search, branch switcher, and actions.
class AppTopBar extends ConsumerWidget {
  const AppTopBar({
    super.key,
    this.pageContext,
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    required this.user,
    this.notificationCount = 0,
    this.onNotificationsClick,
    this.onCommandBarOpen,
    this.isDark = false,
    this.onToggleTheme,
    this.locale = AppLocale.en,
    this.onLocaleChange,
    this.onProfile,
    this.onSignOut,
    this.appVersion = '0.1.0',
    this.toolbarSlot,
  });

  final Widget? pageContext;
  final List<Branch> branches;
  final String currentBranchId;
  final ValueChanged<String> onBranchChange;
  final UserMenuUser user;
  final int notificationCount;
  final VoidCallback? onNotificationsClick;
  final VoidCallback? onCommandBarOpen;
  final bool isDark;
  final VoidCallback? onToggleTheme;
  final AppLocale locale;
  final ValueChanged<AppLocale>? onLocaleChange;
  final VoidCallback? onProfile;
  final VoidCallback? onSignOut;
  final String appVersion;
  final Widget? toolbarSlot;

  static const double _mdBreakpoint = 768;
  static const double _smBreakpoint = 640;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final density = ref.watch(appDensityProvider);
    final topbarHeight = density.shellTopbarHeight;
    final width = MediaQuery.sizeOf(context).width;
    final showPageContext = pageContext != null && width >= _smBreakpoint;
    final showBranchSwitcher = width >= _mdBreakpoint;
    final showKbd = width >= _smBreakpoint;
    final verticalPadding = density == AppDensity.compact
        ? AppSpacing.s1
        : density == AppDensity.comfortable
        ? AppSpacing.s2
        : AppSpacing.s1 + AppSpacing.s0_5;

    return Semantics(
      header: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: SizedBox(
          height: topbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: Row(
              spacing: AppSpacing.s3,
              children: [
                Expanded(
                  child: Row(
                    spacing: AppSpacing.s3,
                    children: [
                      if (showPageContext)
                        Flexible(child: pageContext!),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                  child: _CommandBarTrigger(
                    onOpen: onCommandBarOpen,
                    showKbd: showKbd,
                    verticalPadding: verticalPadding,
                  ),
                ),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        spacing: AppSpacing.s2,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ?toolbarSlot,
                          if (showBranchSwitcher)
                            BranchSwitcher(
                              branches: branches,
                              currentBranchId: currentBranchId,
                              onBranchChange: onBranchChange,
                            ),
                          _NotificationButton(
                            count: notificationCount,
                            onPressed: onNotificationsClick,
                          ),
                          AppIconButton(
                            semanticLabel: isDark
                                ? 'Switch to light theme'
                                : 'Switch to dark theme',
                            icon: isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: AppIconButtonSize.lg,
                            variant: AppIconButtonVariant.ghost,
                            onPressed: onToggleTheme,
                          ),
                          UserMenu(
                            user: user,
                            appVersion: appVersion,
                            isDark: isDark,
                            locale: locale,
                            onProfile: onProfile,
                            onToggleTheme: onToggleTheme,
                            onLocaleChange: onLocaleChange,
                            onSignOut: onSignOut,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandBarTrigger extends StatefulWidget {
  const _CommandBarTrigger({
    required this.onOpen,
    required this.showKbd,
    required this.verticalPadding,
  });

  final VoidCallback? onOpen;
  final bool showKbd;
  final double verticalPadding;

  @override
  State<_CommandBarTrigger> createState() => _CommandBarTriggerState();
}

class _CommandBarTriggerState extends State<_CommandBarTrigger> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final maxWidth = mathMin(
      448,
      MediaQuery.sizeOf(context).width * 0.42,
    );

    return Semantics(
      button: true,
      label: 'Open command bar',
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onOpen?.call();
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
            onTap: widget.onOpen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: maxWidth,
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: widget.verticalPadding,
              ),
              decoration: BoxDecoration(
                color: _hovered ? colors.surfaceHover : colors.surfaceSunken,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: _focused ? colors.focusRing : colors.borderDefault,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 16, color: colors.iconMuted),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      'Search or jump to…',
                      overflow: TextOverflow.ellipsis,
                      style: typography.bodySm.copyWith(
                        color: colors.textPlaceholder,
                      ),
                    ),
                  ),
                  if (widget.showKbd) ...[
                    const SizedBox(width: AppSpacing.s2),
                    const AppKbd(keys: ['⌘', 'K']),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double mathMin(double a, double b) => a < b ? a : b;

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.count,
    this.onPressed,
  });

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = count > 0
        ? 'Notifications, $count unread'
        : 'Notifications';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          semanticLabel: label,
          icon: Icons.notifications_outlined,
          size: AppIconButtonSize.lg,
          variant: AppIconButtonVariant.ghost,
          onPressed: onPressed,
        ),
        if (count > 0)
          PositionedDirectional(
            end: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.statusDangerFg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: context.typography.caption.copyWith(
                    color: colors.textInverse,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
