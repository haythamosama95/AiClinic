import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

import 'settings_permission_action.dart';

/// Tappable settings hub card that navigates to an administration route.
class SettingsNavigationCard extends StatelessWidget {
  const SettingsNavigationCard({
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
    this.disabledReason,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return SettingsPermissionAction(
      disabledReason: disabledReason,
      builder: (enabled) {
        return AppCard(
          variant: enabled ? AppCardVariant.interactive : AppCardVariant.flat,
          onTap: enabled ? onTap : null,
          semanticLabel: title,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadii.mdAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  child: AppIcon(icon: icon, dimension: AppSpacing.s5, color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: typography.bodyStrong.copyWith(color: colors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      description,
                      style: typography.bodySm.copyWith(color: colors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (enabled)
                AppIcon(icon: LucideIcons.chevronRight, dimension: AppSpacing.s4, color: colors.textSecondary),
            ],
          ),
        );
      },
    );
  }
}
