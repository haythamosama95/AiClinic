import 'package:flutter/material.dart';

import 'package:ai_clinic/features/settings/presentation/screens/_empty_screen.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptySettingsScreen(
      icon: Icons.group,
      title: 'Staff',
      description: 'People who sign in and work across your branches.',
      emptyTitle: 'No staff yet',
      emptyDescription: 'Complete the Setup wizard to add your first team member.',
    );
  }
}
