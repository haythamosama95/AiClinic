import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
              Text(featureName, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(routeName, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Text('UI Pending Migration', style: theme.textTheme.titleMedium),
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
