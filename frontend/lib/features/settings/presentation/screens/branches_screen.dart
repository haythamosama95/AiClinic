import 'package:flutter/material.dart';

import 'package:ai_clinic/features/settings/presentation/screens/_empty_screen.dart';

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptySettingsScreen(
      icon: Icons.location_on,
      title: 'Branches',
      description: 'Physical locations where care is delivered.',
      emptyTitle: 'No branches yet',
      emptyDescription: 'Complete the Setup wizard to add your first branch.',
    );
  }
}
