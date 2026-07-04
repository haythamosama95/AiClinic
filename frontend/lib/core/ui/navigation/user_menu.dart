import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/navigation/nav_model.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/display/avatar.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/dropdown_menu.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Avatar trigger with account actions dropdown.
class UserMenu extends StatelessWidget {
  const UserMenu({
    super.key,
    required this.user,
    this.appVersion = '0.1.0',
    this.isDark = false,
    this.locale = AppLocale.en,
    this.onProfile,
    this.onToggleTheme,
    this.onLocaleChange,
    this.onSignOut,
  });

  final UserMenuUser user;
  final String appVersion;
  final bool isDark;
  final AppLocale locale;
  final VoidCallback? onProfile;
  final VoidCallback? onToggleTheme;
  final ValueChanged<AppLocale>? onLocaleChange;
  final VoidCallback? onSignOut;

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      final word = parts.first;
      return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final localeLabel = locale == AppLocale.en ? 'English' : 'العربية';

    return AppPopover(
      placement: const AppPopoverPlacement(
        side: AppPopoverSide.bottom,
        align: AppPopoverAlign.end,
      ),
      minWidth: 224,
      contentPadding: EdgeInsets.zero,
      trigger: Semantics(
        button: true,
        label: 'User menu for ${user.name}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AppAvatar(
            initials: _initials,
            size: AppAvatarSize.sm,
            showStatus: true,
            status: AppAvatarStatus.online,
            semanticLabel: user.name,
          ),
        ),
      ),
      contentBuilder: (context, hide) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s1 + AppSpacing.s0_5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: typography.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (user.role != null) ...[
                      const SizedBox(height: AppSpacing.s0_5),
                      Text(
                        user.role!,
                        style: typography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (user.email != null) ...[
                      const SizedBox(height: AppSpacing.s0_5),
                      Text(
                        user.email!,
                        style: typography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const AppDropdownMenuSeparator(),
              _UserMenuAction(
                icon: Icons.person_outline,
                label: 'Profile',
                onTap: () {
                  hide();
                  onProfile?.call();
                },
              ),
              _UserMenuAction(
                icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                label: isDark ? 'Light theme' : 'Dark theme',
                onTap: () {
                  hide();
                  onToggleTheme?.call();
                },
              ),
              _UserMenuAction(
                icon: Icons.language,
                label: 'Language · $localeLabel',
                onTap: () {
                  hide();
                  onLocaleChange?.call(
                    locale == AppLocale.en ? AppLocale.ar : AppLocale.en,
                  );
                },
              ),
              const AppDropdownMenuSeparator(),
              _UserMenuAction(
                icon: Icons.logout,
                label: 'Sign out',
                destructive: true,
                onTap: () {
                  hide();
                  onSignOut?.call();
                },
              ),
              const AppDropdownMenuSeparator(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s1,
                ),
                child: Text(
                  'v$appVersion',
                  style: typography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserMenuAction extends StatefulWidget {
  const _UserMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_UserMenuAction> createState() => _UserMenuActionState();
}

class _UserMenuActionState extends State<_UserMenuAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final foreground = widget.destructive
        ? colors.statusDangerFg
        : colors.textPrimary;
    final background = _hovered
        ? (widget.destructive
              ? colors.statusDangerSurface
              : colors.surfaceHover)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s1 + AppSpacing.s0_5,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: colors.iconDefault),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    widget.label,
                    style: typography.body.copyWith(color: foreground),
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
