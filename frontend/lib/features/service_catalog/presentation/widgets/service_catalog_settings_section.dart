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
    if (!ref.watch(permissionServiceProvider).canManageServices()) {
      return const SizedBox.shrink();
    }

    return SettingsSectionCard(
      title: 'Service catalog',
      child: SettingsField(
        label: 'Catalog services',
        description: 'Create organization-wide services and assign them to branches for invoicing.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add service',
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.medical_services_outlined, size: 18),
            expand: false,
            onPressed: () => context.push(AppRoutes.settingsServicesNew),
          ),
        ),
      ),
    );
  }
}
