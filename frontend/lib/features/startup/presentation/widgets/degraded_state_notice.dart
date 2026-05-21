import 'package:flutter/material.dart';

import 'package:ai_clinic/shared/providers/connectivity_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';

/// Warns operators when the profile is valid but clinic-local services are not fully reachable.
class DegradedStateNotice extends StatelessWidget {
  const DegradedStateNotice({super.key, required this.connectivityStatus, this.message});

  final StartupConnectivityStatus connectivityStatus;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (title, detail, icon) = _copyForStatus(connectivityStatus, message);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String title, String detail, IconData icon) _copyForStatus(StartupConnectivityStatus status, String? message) {
    return switch (status) {
      StartupConnectivityStatus.degraded => (
        'Degraded clinic-local startup',
        message ??
            'PostgREST responded but another required service failed. Sign-in may not work until API and Auth both return success. '
                'Try Refresh startup checks after `supabase stop` and `supabase start` in the backend folder.',
        Icons.cloud_off_outlined,
      ),
      StartupConnectivityStatus.unreachable => (
        'Clinic-local services unreachable',
        message ??
            'The deployment profile is valid, but the configured server node cannot be reached. Use this screen for troubleshooting while protected work remains blocked.',
        Icons.wifi_off_outlined,
      ),
      _ => ('Startup connectivity notice', message ?? connectivityStatusLabel(status), Icons.info_outline),
    };
  }
}
