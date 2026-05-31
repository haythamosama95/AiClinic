import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';

/// Today's appointment queue for the active branch (V1-4 US4).
class AppointmentQueuePage extends ConsumerWidget {
  const AppointmentQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    final state = ref.watch(appointmentQueueProvider);
    final controller = ref.read(appointmentQueueProvider.notifier);

    if (!canAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text("Today's queue")),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view appointments.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's queue"),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.popOrHome(),
        ),
        actions: [
          IconButton(
            key: const Key('appointments_queue_refresh'),
            tooltip: 'Refresh queue',
            icon: const Icon(Icons.refresh),
            onPressed: state.loading ? null : controller.refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isLive)
            MaterialBanner(
              key: const Key('appointments_queue_live_banner'),
              content: const Text('Live updates connected'),
              leading: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
              actions: const [SizedBox.shrink()],
            ),
          if (state.isDegraded)
            MaterialBanner(
              key: const Key('appointments_queue_degraded_banner'),
              content: const Text('Live updates unavailable. Pull down or tap refresh to update.'),
              leading: Icon(Icons.cloud_off_outlined, color: Theme.of(context).colorScheme.error),
              backgroundColor: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
              actions: [TextButton(onPressed: state.loading ? null : controller.refresh, child: const Text('Refresh'))],
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _QueueBody(state: state, onRetry: controller.refresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.state, required this.onRetry});

  final AppointmentQueueState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))],
      );
    }

    if (state.error != null && state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }

    if (state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        key: const Key('appointments_queue_empty'),
        padding: EdgeInsets.all(24),
        children: [Center(child: Text('No appointments scheduled for today at this branch.'))],
      );
    }

    return ListView.separated(
      key: const Key('appointments_queue_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _QueueRow(item: state.items[index], onStatusChanged: onRetry),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.item, required this.onStatusChanged});

  final AppointmentListItem item;
  final Future<void> Function() onStatusChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeLabel = DateFormat.jm().format(item.startTime.toLocal());
    final statusColor = _statusColor(item.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: Key('appointments_queue_row_${item.id}'),
          title: Text(item.patientName),
          subtitle: Text('${item.doctorDisplayName} · ${item.type.label}'),
          leading: CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.2),
            child: Text(timeLabel, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          trailing: Chip(
            label: Text(item.status.label, style: TextStyle(color: statusColor, fontSize: 12)),
            side: BorderSide(color: statusColor.withValues(alpha: 0.6)),
            backgroundColor: statusColor.withValues(alpha: 0.12),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
          child: AppointmentStatusActions(
            item: item,
            dense: true,
            onStatusChanged: (_) => onStatusChanged(),
            onRescheduled: (_) => onStatusChanged(),
            onVisitChanged: onStatusChanged,
          ),
        ),
      ],
    );
  }

  Color _statusColor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => Colors.blue,
      AppointmentStatus.confirmed => Colors.teal,
      AppointmentStatus.checkedIn => Colors.cyan,
      AppointmentStatus.inProgress => Colors.orange,
      AppointmentStatus.completed => Colors.green,
      AppointmentStatus.cancelled => Colors.red,
      AppointmentStatus.noShow => Colors.deepPurple,
    };
  }
}
