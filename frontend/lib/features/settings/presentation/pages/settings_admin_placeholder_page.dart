import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';

/// Placeholder for V1-2 admin settings screens implemented in later user-story phases.
class SettingsAdminPlaceholderPage extends StatelessWidget {
  const SettingsAdminPlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '$title will be available in the next implementation phase. '
          'Backend RPCs and repositories for this area are already wired.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
