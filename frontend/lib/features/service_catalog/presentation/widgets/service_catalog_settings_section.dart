import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

/// Settings entry point for service catalog administration (015 US1).
class ServiceCatalogSettingsSection extends ConsumerWidget {
  const ServiceCatalogSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canViewServices() && !permissions.canManageServices()) {
      return const SizedBox.shrink();
    }

    return SettingsSectionCard(
      title: 'Service catalog',
      child: SettingsField(
        label: 'Catalog services',
        description: 'Browse, search, and manage organization-wide services for invoicing.',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: 'Browse catalog',
              variant: AppButtonVariant.outline,
              icon: const Icon(Icons.medical_services_outlined, size: 18),
              expand: false,
              onPressed: () => context.push(AppRoutes.settingsServices),
            ),
            if (permissions.canManageServices())
              AppButton(
                label: 'Add service',
                variant: AppButtonVariant.outline,
                icon: const Icon(Icons.add, size: 18),
                expand: false,
                onPressed: () => context.push(AppRoutes.settingsServicesNew),
              ),
          ],
        ),
      ),
    );
  }
}
