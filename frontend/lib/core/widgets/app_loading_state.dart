import 'package:flutter/material.dart';

/// Reusable centered loading panel for startup and other blocking transitions.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.title = 'Preparing AiClinic', this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Keep the loading message readable on wide desktop windows.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 36, height: 36, child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Text(title, style: textTheme.headlineSmall, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
