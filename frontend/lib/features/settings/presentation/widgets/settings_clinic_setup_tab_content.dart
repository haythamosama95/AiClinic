import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';

import 'settings_cards_grid.dart';
import 'settings_navigation_card.dart';

/// Clinic setup tab: links to organization, branch, and permission administration.
class SettingsClinicSetupTabContent extends ConsumerWidget {
  const SettingsClinicSetupTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final canAccess = AuthRouteGuard.canAccessClinicSetup(auth);
    final canManageOrganization = AuthRouteGuard.canAccessOrganizationSettings(auth);
    final canManageBranches = AuthRouteGuard.canAccessBranchManagement(auth);
    final canManagePermissions = AuthRouteGuard.canAccessPermissionMatrix(auth);

    if (!canAccess) {
      return const Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.noAccess,
          title: 'Clinic setup',
          description: 'You do not have permission to manage clinic setup.',
        ),
      );
    }

    return AppScrollArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: SettingsCardsGrid(
          children: [
            if (canManageOrganization)
              SettingsNavigationCard(
                title: 'Organization',
                description: 'Clinic name, currency, timezone, and subscription details.',
                icon: LucideIcons.building2,
                onTap: () => context.nav.goSettingsOrganization(),
              )
            else
              SettingsNavigationCard(
                title: 'Organization',
                description: 'Clinic name, currency, timezone, and subscription details.',
                icon: LucideIcons.building2,
                disabledReason: 'Only clinic administrators can change organization settings.',
              ),
            if (canManageBranches)
              SettingsNavigationCard(
                title: 'Branches',
                description: 'Manage clinic locations, working hours, and branch status.',
                icon: LucideIcons.mapPin,
                onTap: () => context.nav.goSettingsBranches(),
              )
            else
              SettingsNavigationCard(
                title: 'Branches',
                description: 'Manage clinic locations, working hours, and branch status.',
                icon: LucideIcons.mapPin,
                disabledReason: 'You do not have permission to manage branches.',
              ),
            if (canManagePermissions)
              SettingsNavigationCard(
                title: 'Role permissions',
                description: 'Configure which actions each staff role can perform.',
                icon: LucideIcons.shield,
                onTap: () => context.nav.goSettingsPermissions(),
              )
            else
              SettingsNavigationCard(
                title: 'Role permissions',
                description: 'Configure which actions each staff role can perform.',
                icon: LucideIcons.shield,
                disabledReason: 'Role permissions are available only to clinic administrators.',
              ),
          ],
        ),
      ),
    );
  }
}
