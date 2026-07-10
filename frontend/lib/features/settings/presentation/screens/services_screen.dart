import 'package:flutter/material.dart';

import 'package:ai_clinic/features/settings/presentation/screens/_empty_screen.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptySettingsScreen(
      icon: Icons.medical_services,
      title: 'Services',
      description: 'Billable procedures in your catalog.',
      emptyTitle: 'No services yet',
      emptyDescription: 'Complete the Setup wizard to add your first service.',
    );
  }
}
