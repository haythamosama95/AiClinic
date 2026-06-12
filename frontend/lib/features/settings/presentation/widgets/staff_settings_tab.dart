import 'package:flutter/material.dart';

import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';

/// Staff accounts settings: list, filter, and lifecycle actions.
class StaffSettingsTab extends StatelessWidget {
  const StaffSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const StaffListPage(embedded: true);
  }
}
