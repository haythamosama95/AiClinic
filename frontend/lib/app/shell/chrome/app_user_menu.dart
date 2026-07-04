import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Avatar trigger with profile, settings, and sign-out actions.
class AppUserMenu extends ConsumerWidget {
  const AppUserMenu({
    this.appVersion = '1.0.0',
    super.key,
  });

  /// Application version shown in the menu footer.
  final String appVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final auth = ref.watch(authSessionProvider);
    final contextData = auth.context;
    if (contextData == null) {
      return const SizedBox.shrink();
    }

    final profile = contextData.staffProfile;
    final staffId = profile.staffMemberId;

    return AppDropdownMenu(
      align: AppDropdownMenuAlign.end,
      minWidth: AppSpacing.s12 * 3 + AppSpacing.s8,
      trigger: (context, show, hide, toggle) {
        return AppPressable(
          onTap: show,
          semanticLabel: 'User menu for ${profile.fullName}',
          borderRadius: AppRadii.fullAll,
          child: AppAvatar(
            name: profile.fullName,
            size: AppAvatarSize.sm,
            showStatus: true,
            status: AppAvatarStatus.online,
          ),
        );
      },
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s2,
            AppSpacing.s2,
            AppSpacing.s2,
            AppSpacing.s1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.fullName,
                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              Text(
                profile.role.displayLabel,
                style: typography.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const AppDropdownMenuSeparator(),
        AppDropdownMenuItem(
          label: 'Profile',
          leading: LucideIcons.user,
          onSelected: () => context.go(AppRoutes.settingsStaffDetail(staffId)),
        ),
        AppDropdownMenuItem(
          label: 'Settings',
          leading: LucideIcons.settings,
          onSelected: () => context.go(AppRoutes.settings),
        ),
        const AppDropdownMenuSeparator(),
        AppDropdownMenuItem(
          label: 'Sign out',
          leading: LucideIcons.logOut,
          destructive: true,
          onSelected: () => ref.read(authSessionProvider.notifier).signOut(),
        ),
        const AppDropdownMenuSeparator(),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s2,
            vertical: AppSpacing.s1,
          ),
          child: Text(
            'v$appVersion',
            style: typography.caption.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}
