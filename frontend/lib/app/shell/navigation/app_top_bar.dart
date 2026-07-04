import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/navigation/app_branch_switcher.dart';
import 'package:ai_clinic/app/shell/navigation/app_command_bar_trigger.dart';
import 'package:ai_clinic/app/shell/navigation/app_user_menu.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_model.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Sticky top chrome for the authenticated shell (`04-components` C2, web `AppTopBar`).
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    required this.user,
    required this.isDarkTheme,
    required this.onToggleTheme,
    this.pageContext,
    this.notificationCount = 0,
    this.onNotificationsPressed,
    this.onSignOut,
    this.toolbarSlot,
    super.key,
  });

  final Widget? pageContext;
  final List<ShellBranch> branches;
  final String? currentBranchId;
  final ValueChanged<String> onBranchChange;
  final ShellUser user;
  final int notificationCount;
  final VoidCallback? onNotificationsPressed;
  final bool isDarkTheme;
  final VoidCallback onToggleTheme;
  final VoidCallback? onSignOut;
  final Widget? toolbarSlot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final width = MediaQuery.sizeOf(context).width;

    return Material(
      color: colors.surfaceDefault,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: SizedBox(
          height: AppShellTokens.topBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: pageContext != null && width >= 640 ? pageContext! : const SizedBox.shrink(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                  child: AppCommandBarTrigger(),
                ),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ?toolbarSlot,
                        if (width >= 768) ...[
                          AppBranchSwitcher(
                            branches: branches,
                            currentBranchId: currentBranchId,
                            onBranchChange: onBranchChange,
                          ),
                          const SizedBox(width: AppSpacing.space2),
                        ],
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AppIconButton(
                              icon: const Icon(Icons.notifications_outlined),
                              tooltip: notificationCount > 0
                                  ? 'Notifications, $notificationCount unread'
                                  : 'Notifications',
                              size: AppIconButtonSize.lg,
                              onPressed: onNotificationsPressed,
                            ),
                            if (notificationCount > 0)
                              PositionedDirectional(
                                end: 6,
                                top: 6,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: colors.statusDangerFg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    notificationCount > 9 ? '9+' : '$notificationCount',
                                    style: AppTypography.bodySm(context).copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textInverse,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (width >= 480)
                          AppIconButton(
                            icon: Icon(isDarkTheme ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                            tooltip: isDarkTheme ? 'Switch to light theme' : 'Switch to dark theme',
                            size: AppIconButtonSize.lg,
                            onPressed: onToggleTheme,
                          ),
                        AppUserMenu(user: user, onToggleTheme: onToggleTheme, onSignOut: onSignOut),
                      ],
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

/// Simple page context label used in the top bar until breadcrumbs are ported.
class AppTopBarPageLabel extends StatelessWidget {
  const AppTopBarPageLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong(context));
  }
}
