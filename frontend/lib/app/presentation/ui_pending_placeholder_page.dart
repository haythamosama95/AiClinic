import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';

/// Temporary route target shown while feature UI is being rebuilt.
class UiPendingPlaceholderPage extends StatelessWidget {
  const UiPendingPlaceholderPage({required this.featureName, required this.routeName, super.key});

  final String featureName;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(featureName, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(routeName, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Text('UI Pending Migration', style: theme.textTheme.titleMedium),
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => context.nav.goFoundationDemo(),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Design System'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds a placeholder page for the given feature and current route.
Widget uiPendingPlaceholder(String featureName, GoRouterState state) {
  return UiPendingPlaceholderPage(featureName: featureName, routeName: state.matchedLocation);
}
