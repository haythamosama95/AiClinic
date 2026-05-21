import 'package:flutter/material.dart';

/// Blocked placeholder when the user is signed in but has no branch assignments (FR-007a).
class NoBranchBlockedPanel extends StatelessWidget {
  const NoBranchBlockedPanel({super.key, required this.staffName});

  final String staffName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined, size: 56, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('No branch assigned', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Signed in as $staffName, but this account is not linked to any clinic branch yet. '
                'Branch-scoped features stay unavailable until a clinic owner or administrator assigns you to at least one branch.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Contact your clinic administrator to request a branch assignment, then sign in again.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
