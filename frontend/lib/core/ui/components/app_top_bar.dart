import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/components/app_branch_switcher.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/components/app_user_menu.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/command_bar_controller.dart';

/// Sticky top chrome (web `AppTopBar`).
class AppTopBar extends ConsumerStatefulWidget {
  const AppTopBar({
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    required this.user,
    this.pageContext,
    this.notificationCount = 0,
    this.onNotificationsClick,
    this.onSignOut,
    this.toolbarSlot,
    super.key,
  });

  final Widget? pageContext;
  final List<AppBranch> branches;
  final String currentBranchId;
  final ValueChanged<String> onBranchChange;
  final AppUserMenuUser user;
  final int notificationCount;
  final VoidCallback? onNotificationsClick;
  final VoidCallback? onSignOut;
  final Widget? toolbarSlot;

  @override
  ConsumerState<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends ConsumerState<AppTopBar> {
  final _triggerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(commandBarProvider.notifier).registerTrigger(_triggerKey);
    });
  }

  @override
  void dispose() {
    ref.read(commandBarProvider.notifier).registerTrigger(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Material(
      color: colors.surfaceDefault,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: SizedBox(
          height: AppShellTokens.topBarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: widget.pageContext != null && barWidth >= 640
                            ? widget.pageContext!
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: barWidth >= 640 ? 448 : 280),
                        child: Focus(
                          key: _triggerKey,
                          child: AppPressable(
                            onPressed: () => ref.read(commandBarProvider.notifier).openCommandBar(),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: colors.borderDefault),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 16, color: colors.iconMuted),
                                    const SizedBox(width: AppSpacing.space2),
                                    Expanded(
                                      child: Text(
                                        'Search or jump to…',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.bodySm(context).copyWith(color: colors.textPlaceholder),
                                      ),
                                    ),
                                    if (barWidth >= 640) ...[
                                      const SizedBox(width: AppSpacing.space2),
                                      const AppKbd(keys: ['⌘', 'K']),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          clipBehavior: Clip.hardEdge,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ?widget.toolbarSlot,
                              if (widget.branches.isNotEmpty) ...[
                                AppBranchSwitcher(
                                  branches: widget.branches,
                                  currentBranchId: widget.currentBranchId,
                                  onBranchChange: widget.onBranchChange,
                                ),
                                const SizedBox(width: AppSpacing.space2),
                              ],
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AppIconButton(
                                    icon: const Icon(Icons.notifications_outlined, size: 24),
                                    label: widget.notificationCount > 0
                                        ? 'Notifications, ${widget.notificationCount} unread'
                                        : 'Notifications',
                                    size: AppIconButtonSize.lg,
                                    onPressed: widget.onNotificationsClick,
                                  ),
                                  if (widget.notificationCount > 0)
                                    PositionedDirectional(
                                      end: 6,
                                      top: 6,
                                      child: Container(
                                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: colors.statusDangerFg,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          widget.notificationCount > 9 ? '9+' : '${widget.notificationCount}',
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
                              AppIconButton(
                                icon: Icon(isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 24),
                                label: isLight ? 'Switch to dark theme' : 'Switch to light theme',
                                size: AppIconButtonSize.lg,
                                onPressed: () => setAppThemeMode(ref, isLight ? ThemeMode.dark : ThemeMode.light),
                              ),
                              AppUserMenu(user: widget.user, onSignOut: widget.onSignOut),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
