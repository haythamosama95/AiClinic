import 'package:flutter/material.dart';

/// Informational placeholder until visit documentation ships in V1-5.
class PatientVisitsPlaceholder extends StatelessWidget {
  const PatientVisitsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: const Key('patient_visits_placeholder'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_note_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Visit history', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Visit records will appear here after clinical documentation is enabled. '
                    'For now, use patient notes above for context.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
