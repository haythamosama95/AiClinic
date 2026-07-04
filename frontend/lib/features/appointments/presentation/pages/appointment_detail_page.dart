import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_presentation_formatting.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_section.dart';

/// Full appointment profile page loaded via `get_appointment`.
class AppointmentDetailPage extends ConsumerWidget {
  const AppointmentDetailPage({
    required this.appointmentId,
    this.preview,
    super.key,
  });

  final String appointmentId;

  /// Optional list-row preview while the profile loads.
  final AppointmentListItem? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Appointment detail',
        description: 'You do not have permission to view this appointment.',
      );
    }

    final detailAsync = ref.watch(appointmentDetailProvider(appointmentId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => RecordDetailPattern(
        title: preview?.patientName ?? 'Appointment detail',
        description: preview?.status.label,
        statusBadge: preview == null
            ? null
            : AppBadge(
                color: AppointmentPresentationFormatting.badgeColorFor(preview!.status),
                child: Text(preview!.status.label),
              ),
        body: const Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Appointment detail',
        body: AppErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(appointmentDetailProvider(appointmentId)),
        ),
      ),
      data: (detail) => RecordDetailPattern(
        title: detail.patientName,
        description:
            'with ${detail.doctorDisplayName} · ${AppointmentPresentationFormatting.formatTimeRange(detail.startTime, detail.endTime)}',
        statusBadge: AppBadge(
          color: AppointmentPresentationFormatting.badgeColorFor(detail.status),
          child: Text(detail.status.label),
        ),
        actions: AppButton(
          label: 'Patient profile',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          leadingIcon: LucideIcons.user,
          onPressed: () => context.nav.pushPatientDetail(detail.patientId),
        ),
        body: _AppointmentDetailBody(detail: detail),
      ),
    );
  }
}

class _AppointmentDetailBody extends StatelessWidget {
  const _AppointmentDetailBody({required this.detail});

  final AppointmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final durationMinutes = detail.endTime.difference(detail.startTime).inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDescriptionList(
          items: [
            AppDescriptionItem(
              label: 'Date',
              value: Text(AppointmentPresentationFormatting.formatDate(detail.startTime)),
            ),
            AppDescriptionItem(
              label: 'Time',
              value: Text(AppointmentPresentationFormatting.formatTimeRange(detail.startTime, detail.endTime)),
            ),
            AppDescriptionItem(
              label: 'Duration',
              value: Text(AppointmentPresentationFormatting.formatDurationMinutes(durationMinutes)),
            ),
            AppDescriptionItem(label: 'Type', value: Text(detail.type.label)),
            if (detail.queueNumber != null)
              AppDescriptionItem(
                label: 'Queue number',
                value: Text('${detail.queueNumber}'),
                tabular: true,
              ),
            if (detail.createdByDisplay?.trim().isNotEmpty == true)
              AppDescriptionItem(label: 'Booked by', value: Text(detail.createdByDisplay!)),
            AppDescriptionItem(
              label: 'Last updated',
              value: Text(AppointmentPresentationFormatting.formatAuditTimestamp(detail.updatedAt)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        AppointmentStatusTimelineSection(detail: detail),
        if (detail.notes?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.s6),
          AppAlert(
            variant: AppAlertVariant.info,
            title: 'Notes',
            body: detail.notes!.trim(),
          ),
        ],
        if (detail.cancelReason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.s4),
          AppAlert(
            variant: AppAlertVariant.warning,
            title: 'Cancellation reason',
            body: detail.cancelReason!.trim(),
          ),
        ],
      ],
    );
  }
}
