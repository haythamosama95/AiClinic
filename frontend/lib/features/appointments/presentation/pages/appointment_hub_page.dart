import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Appointments entry hub: links to book, walk-in, queue, and calendar (V1-4).
class AppointmentHubPage extends ConsumerWidget {
  const AppointmentHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canAccess = permissions.canAccessAppointments();
    final canCreate = permissions.canCreateAppointments();
    final activeBranchId = ref.watch(authSessionProvider).context?.activeBranchId;
    final missingBranch = activeBranchId == null || activeBranchId.isEmpty;

    if (!canAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Appointments'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.nav.goHome(),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to access appointments.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scheduling at your active branch',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (missingBranch) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Select an active branch in the status bar before booking or registering walk-ins.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                if (canCreate) ...[
                  FilledButton.icon(
                    key: const Key('appointments_hub_book'),
                    onPressed: missingBranch ? null : () => context.nav.goAppointmentsBook(),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Book appointment'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('appointments_hub_walk_in'),
                    onPressed: missingBranch ? null : () => context.nav.goAppointmentsWalkIn(),
                    icon: const Icon(Icons.directions_walk_outlined),
                    label: const Text('Register walk-in'),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.tonalIcon(
                  key: const Key('appointments_hub_queue'),
                  onPressed: missingBranch ? null : () => context.nav.goAppointmentsQueue(),
                  icon: const Icon(Icons.queue_outlined),
                  label: const Text("Today's queue"),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('appointments_hub_calendar'),
                  onPressed: missingBranch ? null : () => context.nav.goAppointmentsCalendar(),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Calendar & schedules'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Calendar, walk-in auto-slot, and live queue views are added in upcoming releases. '
                  'Planned booking is available now.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
