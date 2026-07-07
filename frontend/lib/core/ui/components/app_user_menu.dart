import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

/// Account menu in the top bar (web `UserMenu`).
class AppUserMenu extends ConsumerStatefulWidget {
  const AppUserMenu({required this.user, this.onSignOut, this.appVersion = '0.1.0', this.triggerSize = 40, super.key});

  final AppUserMenuUser user;
  final VoidCallback? onSignOut;
  final String appVersion;

  /// Outer trigger footprint; defaults to [AppIconButtonSize.lg] for top-bar alignment.
  final double triggerSize;

  @override
  ConsumerState<AppUserMenu> createState() => _AppUserMenuState();
}

class _AppUserMenuState extends ConsumerState<AppUserMenu> {
  var _open = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final locale = ref.watch(devPreviewProvider).locale;

    return AppPopover(
      open: _open,
      onOpenChange: (value) => setState(() => _open = value),
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      width: 224,
      triggerBuilder: (context, isOpen, onToggle) {
        return Semantics(
          button: true,
          label: 'User menu for ${widget.user.name}',
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedOpacity(
              opacity: _hovered || isOpen ? 0.9 : 1,
              duration: const Duration(milliseconds: 120),
              child: SizedBox(
                width: widget.triggerSize,
                height: widget.triggerSize,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggle,
                    customBorder: const CircleBorder(),
                    child: AppAvatar(
                      name: widget.user.name,
                      dimension: widget.triggerSize,
                      showStatus: true,
                      status: AvatarStatus.online,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.name, style: AppTypography.bodyStrong(context)),
                Text(widget.user.role, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
                if (widget.user.email.isNotEmpty)
                  Text(widget.user.email, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
              ],
            ),
          ),
          const Divider(height: 1),
          _UserMenuItem(icon: Icons.person_outline, label: 'Profile', onTap: () => setState(() => _open = false)),
          _UserMenuItem(
            icon: isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label: isLight ? 'Dark theme' : 'Light theme',
            onTap: () {
              setAppThemeMode(ref, isLight ? ThemeMode.dark : ThemeMode.light);
              setState(() => _open = false);
            },
          ),
          _UserMenuItem(
            icon: Icons.language,
            label: 'Language · ${locale == 'en' ? 'English' : 'العربية'}',
            onTap: () {
              ref.read(devPreviewProvider.notifier).setLocale(locale == 'en' ? 'ar' : 'en');
              setState(() => _open = false);
            },
          ),
          const Divider(height: 1),
          _UserMenuItem(
            icon: Icons.logout,
            label: 'Sign out',
            destructive: true,
            onTap: () {
              setState(() => _open = false);
              widget.onSignOut?.call();
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
            child: Text(
              'v${widget.appVersion}',
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMenuItem extends StatelessWidget {
  const _UserMenuItem({required this.icon, required this.label, required this.onTap, this.destructive = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = destructive ? colors.statusDangerFg : colors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(label, style: AppTypography.bodySm(context).copyWith(color: foreground)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
