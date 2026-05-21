import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Post-login clinic workstation settings (session policies, etc.).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idleSettings = ref.watch(idleTimeoutSettingsProvider);
    final auth = ref.watch(authSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.home)),
      ),
      body: ListView(
        children: [
          if (AuthRouteGuard.canAccessOrganizationSettings(auth) ||
              AuthRouteGuard.canAccessBranchManagement(auth) ||
              AuthRouteGuard.canAccessStaffManagement(auth) ||
              AuthRouteGuard.canAccessPermissionMatrix(auth)) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Clinic administration', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (AuthRouteGuard.canAccessOrganizationSettings(auth))
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: const Text('Organization'),
                subtitle: const Text('Name, logo, currency, and timezone'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.settingsOrganization),
              ),
            if (AuthRouteGuard.canAccessBranchManagement(auth))
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text('Branches'),
                subtitle: const Text('Create, edit, and deactivate branches'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.settingsBranches),
              ),
            if (AuthRouteGuard.canAccessStaffManagement(auth))
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Staff'),
                subtitle: const Text('Manage staff accounts and branch assignments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.settingsStaff),
              ),
            if (AuthRouteGuard.canAccessPermissionMatrix(auth))
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Role permissions'),
                subtitle: const Text('View or edit the permission matrix'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.settingsPermissions),
              ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Workstation', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          idleSettings.when(
            data: (settings) => ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Idle sign-out'),
              subtitle: Text(
                'Automatically sign out after ${IdleTimeoutConfig.formatDuration(settings.duration)} without keyboard or pointer input.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.settingsIdleTimeout),
            ),
            loading: () => const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('Idle sign-out'),
              subtitle: Text('Loading…'),
            ),
            error: (_, _) => ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Idle sign-out'),
              subtitle: const Text('Could not load current value'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.settingsIdleTimeout),
            ),
          ),
        ],
      ),
    );
  }
}
