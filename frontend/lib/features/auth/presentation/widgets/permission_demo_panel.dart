import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Demo controls to verify RBAC gating on the placeholder shell (US3 checkpoint).
class PermissionDemoPanel extends ConsumerWidget {
  const PermissionDemoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Permission demo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Sample actions below reflect your role. Unauthorized actions show a brief denial message.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (permissions.hasPermission(PermissionKeys.manageStaff))
              _DemoActionButton(
                label: 'Manage staff (granted)',
                icon: Icons.group_add_outlined,
                onPressed: () => _showGrantedSnackBar(context, 'Staff management'),
              ),
            _DemoActionButton(
              label: permissions.hasPermission(PermissionKeys.analyticsView)
                  ? 'View analytics (granted)'
                  : 'View analytics (denied demo)',
              icon: Icons.insights_outlined,
              onPressed: () => _attempt(
                context,
                permissions: permissions,
                key: PermissionKeys.analyticsView,
                grantedLabel: 'Analytics',
              ),
            ),
            _DemoActionButton(
              label: permissions.hasPermission(PermissionKeys.invoicesCreate)
                  ? 'Create invoice (granted)'
                  : 'Create invoice (denied demo)',
              icon: Icons.receipt_long_outlined,
              onPressed: () => _attempt(
                context,
                permissions: permissions,
                key: PermissionKeys.invoicesCreate,
                grantedLabel: 'Invoice creation',
              ),
            ),
            _DemoActionButton(
              label: 'Try staff settings (always visible)',
              icon: Icons.admin_panel_settings_outlined,
              onPressed: () => _attempt(
                context,
                permissions: permissions,
                key: PermissionKeys.manageStaff,
                grantedLabel: 'Staff settings',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _attempt(
    BuildContext context, {
    required PermissionService permissions,
    required String key,
    required String grantedLabel,
  }) {
    PermissionDeniedHandler.runIfPermitted(
      context,
      permissions: permissions,
      permissionKey: key,
      action: () => _showGrantedSnackBar(context, grantedLabel),
    );
  }

  void _showGrantedSnackBar(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is permitted for your role.'), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DemoActionButton extends StatelessWidget {
  const _DemoActionButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label)),
    );
  }
}
