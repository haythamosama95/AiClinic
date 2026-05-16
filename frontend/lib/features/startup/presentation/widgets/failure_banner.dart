import 'package:flutter/material.dart';

import 'package:ai_clinic/core/errors/failures.dart';

/// Highlights configuration or connectivity failures without leaving the startup flow.
class FailureBanner extends StatelessWidget {
  const FailureBanner({super.key, required this.failure});

  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failure.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onErrorContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    failure.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
