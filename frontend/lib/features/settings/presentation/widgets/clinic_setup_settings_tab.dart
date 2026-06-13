import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/branch_settings_section.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/organization_settings_section.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';

/// Clinic setup settings: organization and branch configuration.
class ClinicSetupSettingsTab extends ConsumerWidget {
  const ClinicSetupSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final canAccess = AuthRouteGuard.canAccessClinicSetup(auth);
    final canManageOrganization = AuthRouteGuard.canAccessOrganizationSettings(auth);
    final canManageBranches = AuthRouteGuard.canAccessBranchManagement(auth);

    if (!canAccess) {
      return const _CenteredMessage('You do not have permission to manage clinic setup.');
    }

    final organizationAsync = ref.watch(clinicSetupOrganizationProvider);
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        if (canManageOrganization)
          organizationAsync.when(
            loading: () => const _ClinicSetupLoadingCard(title: 'Organization'),
            error: (_, _) => const AppAlert(
              variant: AppAlertVariant.destructive,
              title: 'Unable to load organization settings. Check connectivity and try again.',
            ),
            data: (profile) {
              if (profile == null) {
                return const AppAlert(
                  variant: AppAlertVariant.destructive,
                  title: 'Your clinic organization could not be found.',
                );
              }
              return OrganizationSettingsSection(profile: profile, canManageBranches: canManageBranches);
            },
          ),
        if (canManageOrganization && canManageBranches) const SizedBox(height: SpacingTokens.lg),
        if (canManageBranches)
          branchesAsync.when(
            loading: () => const _ClinicSetupLoadingCard(title: 'Branches'),
            error: (_, _) => const AppAlert(
              variant: AppAlertVariant.destructive,
              title: 'Unable to load branches. Check connectivity and try again.',
            ),
            data: (branches) {
              if (branches.isEmpty) {
                return const AppAlert(title: 'No branches were found for your clinic.');
              }

              return SettingsCardsGrid(
                children: [
                  for (final branch in branches) BranchSettingsSection(branch: branch, canManage: canManageBranches),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ClinicSetupLoadingCard extends StatelessWidget {
  const _ClinicSetupLoadingCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.lg),
            const Center(child: AppCircularProgress()),
          ],
        ),
      ),
    );
  }
}
