import 'package:flutter/material.dart';

import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';

/// Staff roles and permissions settings.
class StaffRolesSettingsTab extends StatelessWidget {
  const StaffRolesSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePermissionsPage(embedded: true);
  }
}
