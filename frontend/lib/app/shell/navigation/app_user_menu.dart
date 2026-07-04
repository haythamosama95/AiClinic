import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/navigation/shell_nav_model.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Account menu in the top bar (`04-components` C10).
class AppUserMenu extends StatelessWidget {
  const AppUserMenu({required this.user, this.onToggleTheme, this.onSignOut, this.appVersion = '1.0.0', super.key});

  final ShellUser user;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onSignOut;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
        surfaceTintColor: WidgetStatePropertyAll(colors.surfaceRaised),
        minimumSize: const WidgetStatePropertyAll(Size(224, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: colors.borderDefault),
          ),
        ),
      ),
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          customBorder: const CircleBorder(),
          child: AppAvatar(name: user.name),
        );
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: AppTypography.bodyStrong(context)),
              if (user.role != null)
                Text(user.role!, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
              if (user.email != null)
                Text(user.email!, style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary)),
            ],
          ),
        ),
        const Divider(height: 1),
        MenuItemButton(
          onPressed: onToggleTheme,
          leadingIcon: const Icon(Icons.dark_mode_outlined, size: 16),
          child: const Text('Toggle theme'),
        ),
        MenuItemButton(
          onPressed: onSignOut,
          leadingIcon: Icon(Icons.logout, size: 16, color: colors.statusDangerFg),
          child: Text('Sign out', style: TextStyle(color: colors.statusDangerFg)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
          child: Text('v$appVersion', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary)),
        ),
      ],
    );
  }
}
