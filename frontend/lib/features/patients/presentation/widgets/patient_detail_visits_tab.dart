import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Visits tab — past visits and upcoming appointments on a shared timeline.
class PatientDetailVisitsTab extends ConsumerWidget {
  const PatientDetailVisitsTab({required this.detail, super.key});

  final PatientDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyQuery = PatientDetailHistoryQuery(
      patientId: detail.id,
      branchId: detail.branchId,
    );
    final pastVisitsAsync = ref.watch(patientPastVisitsProvider(detail.id));
    final upcomingAsync = ref.watch(patientUpcomingAppointmentsProvider(historyQuery));
    final selectedTab = ref.watch(patientDetailHistoryTabProvider(detail.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTabs(
          variant: AppTabsVariant.segmented,
          items: [
            AppTabItem(
              id: PatientDetailHistoryTab.past.name,
              label: 'Past visits',
              count: pastVisitsAsync.value?.length,
            ),
            AppTabItem(
              id: PatientDetailHistoryTab.upcoming.name,
              label: 'Upcoming',
              count: upcomingAsync.value?.length,
            ),
          ],
          selectedId: selectedTab.name,
          onChanged: (id) {
            final tab = PatientDetailHistoryTab.values.byName(id);
            ref.read(patientDetailHistoryTabProvider(detail.id).notifier).select(tab);
          },
          semanticLabel: 'Visit history sections',
        ),
        const SizedBox(height: AppSpacing.s6),
        AnimatedSwitcher(
          duration: AppMotion.resolvePreset(AppMotionPreset.tab, reduced: AppMotion.reduced(context)).duration,
          child: switch (selectedTab) {
            PatientDetailHistoryTab.past => _PastVisitsPanel(
              key: const ValueKey('past'),
              pastVisitsAsync: pastVisitsAsync,
              onRetry: () => ref.invalidate(patientPastVisitsProvider(detail.id)),
            ),
            PatientDetailHistoryTab.upcoming => _UpcomingAppointmentsPanel(
              key: const ValueKey('upcoming'),
              upcomingAsync: upcomingAsync,
              branchName: detail.branchName,
              onRetry: () => ref.invalidate(patientUpcomingAppointmentsProvider(historyQuery)),
            ),
          },
        ),
      ],
    );
  }
}

class _PastVisitsPanel extends StatelessWidget {
  const _PastVisitsPanel({
    required this.pastVisitsAsync,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<List<VisitListItem>> pastVisitsAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return pastVisitsAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (_, _) => AppErrorState(
        message: 'Unable to load past visits.',
        onRetry: onRetry,
      ),
      data: (visits) {
        if (visits.isEmpty) {
          return const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No past visits recorded',
            description: 'Completed visits will appear on this timeline.',
          );
        }

        return AppTimeline(
          events: [
            for (final visit in visits)
              AppTimelineEvent(
                id: visit.id,
                timestamp: PatientPresentationFormatting.dateTime.format(visit.visitDate.toLocal()),
                title: visit.doctorName,
                description: Text('${visit.branchName} · ${visit.status.label}'),
                group: _timelineGroupLabel(visit.visitDate),
              ),
          ],
        );
      },
    );
  }
}

class _UpcomingAppointmentsPanel extends StatelessWidget {
  const _UpcomingAppointmentsPanel({
    required this.upcomingAsync,
    required this.branchName,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<List<AppointmentListItem>> upcomingAsync;
  final String branchName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return upcomingAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (_, _) => AppErrorState(
        message: 'Unable to load upcoming appointments.',
        onRetry: onRetry,
      ),
      data: (appointments) {
        if (appointments.isEmpty) {
          return const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No upcoming appointments scheduled',
            description: 'Book an appointment to see it here.',
          );
        }

        return AppTimeline(
          events: [
            for (final appointment in appointments)
              AppTimelineEvent(
                id: appointment.id,
                timestamp: PatientPresentationFormatting.dateTime.format(appointment.startTime.toLocal()),
                title: appointment.doctorDisplayName,
                description: Text('$branchName · ${appointment.status.label}'),
                group: _timelineGroupLabel(appointment.startTime),
              ),
          ],
        );
      },
    );
  }
}

String _timelineGroupLabel(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final eventDay = DateTime(local.year, local.month, local.day);
  final diff = eventDay.difference(today).inDays;

  if (diff == 0) {
    return 'Today';
  }
  if (diff == 1) {
    return 'Tomorrow';
  }
  if (diff == -1) {
    return 'Yesterday';
  }
  return PatientPresentationFormatting.date.format(local);
}
