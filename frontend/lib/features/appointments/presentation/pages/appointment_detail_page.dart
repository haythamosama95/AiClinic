import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_siblings_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_edit_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_motion.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_widget.dart';

/// Full appointment profile page loaded via `get_appointment`.
class AppointmentDetailPage extends ConsumerWidget {
  const AppointmentDetailPage({required this.appointmentId, this.extra, super.key});

  final String appointmentId;
  final AppointmentDetailRouteExtra? extra;

  AppointmentListItem? get _preview => extra?.preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const _AppointmentDetailPermissionDenied();
    }

    final detailAsync = ref.watch(appointmentDetailProvider(appointmentId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => _AppointmentDetailLoadingView(
        appointmentId: appointmentId,
        preview: _preview,
        onBack: () => _goBack(context),
      ),
      error: (error, _) {
        if (error is RpcFailure && error.code == 'NOT_FOUND') {
          return _AppointmentDetailNotFoundView(onBack: () => _goBack(context));
        }
        return _AppointmentDetailErrorView(
          appointmentId: appointmentId,
          message: error.toString(),
          onBack: () => _goBack(context),
          onRetry: () => ref.invalidate(appointmentDetailProvider(appointmentId)),
        );
      },
      data: (detail) => _AppointmentDetailContentView(
        detail: detail,
        preview: _preview,
        onBack: () => _goBack(context),
        onChanged: () => _invalidateSurfaces(ref, detail),
      ),
    );
  }

  static void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goAppointmentsCalendar();
  }

  static void _invalidateSurfaces(WidgetRef ref, AppointmentDetail detail) {
    ref.invalidate(appointmentDetailProvider(detail.id));
    ref.invalidate(
      appointmentDetailSiblingsProvider(
        AppointmentDetailSiblingsQuery(branchId: detail.branchId, startTime: detail.startTime),
      ),
    );
    ref.invalidate(
      appointmentDetailShiftLookupProvider(
        AppointmentDetailShiftQuery(branchId: detail.branchId, appointmentStart: detail.startTime),
      ),
    );
    ref.invalidate(appointmentCalendarProvider);
  }
}

class _AppointmentDetailContentView extends ConsumerWidget {
  const _AppointmentDetailContentView({
    required this.detail,
    required this.onBack,
    required this.onChanged,
    this.preview,
  });

  final AppointmentDetail detail;
  final AppointmentListItem? preview;
  final VoidCallback onBack;
  final VoidCallback onChanged;

  static final _dateFormat = DateFormat('EEEE, MMM d, yyyy');
  static final _timeFormat = DateFormat('h:mm a');
  static final _auditFormat = DateFormat('MMM d, yyyy · h:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final statusColor = AppointmentCalendarDisplay.statusColor(detail.status, brightness);
    final durationMinutes = detail.endTime.difference(detail.startTime).inMinutes;

    final siblingsQuery = AppointmentDetailSiblingsQuery(branchId: detail.branchId, startTime: detail.startTime);
    final shiftQuery = AppointmentDetailShiftQuery(branchId: detail.branchId, appointmentStart: detail.startTime);
    final siblingsAsync = ref.watch(appointmentDetailSiblingsProvider(siblingsQuery));
    final shiftAsync = ref.watch(appointmentDetailShiftLookupProvider(shiftQuery));
    final siblings = siblingsAsync.value ?? const <AppointmentListItem>[];
    final shiftLookup = shiftAsync.value ?? AppointmentQueueShiftDoctorLookup.empty;

    return _AppointmentDetailScaffold(
      title: detail.patientName,
      subtitle: detail.status.label,
      patientId: detail.patientId,
      headerActions: [AppointmentDetailEditButton(detail: detail)],
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppointmentHeroCard(
            detail: detail,
            statusColor: statusColor,
            dateLabel: _dateFormat.format(detail.startTime.toLocal()),
            timeLabel:
                '${_timeFormat.format(detail.startTime.toLocal())} – ${_timeFormat.format(detail.endTime.toLocal())}',
            durationLabel: '$durationMinutes min',
            auditFormat: _auditFormat,
          ),
          const SizedBox(height: AppSpacing.space6),
          AppointmentStatusTimelineWidget(
            detail: detail,
            siblingAppointments: siblings,
            shiftLookup: shiftLookup,
            onChanged: onChanged,
          ),
          if (detail.notes?.trim().isNotEmpty == true || detail.cancelReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.space6),
            if (detail.notes?.trim().isNotEmpty == true)
              _AppointmentNotesCard(
                title: 'Notes',
                body: detail.notes!.trim(),
                icon: Icons.sticky_note_2_outlined,
                accent: context.appColors.textLink,
              ),
            if (detail.cancelReason?.trim().isNotEmpty == true) ...[
              if (detail.notes?.trim().isNotEmpty == true) const SizedBox(height: AppSpacing.space4),
              _AppointmentNotesCard(
                title: 'Cancellation reason',
                body: detail.cancelReason!.trim(),
                icon: Icons.info_outline_rounded,
                accent: context.appColors.actionDanger,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AppointmentHeroCard extends StatelessWidget {
  const _AppointmentHeroCard({
    required this.detail,
    required this.statusColor,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
    required this.auditFormat,
  });

  final AppointmentDetail detail;
  final Color statusColor;
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;
  final DateFormat auditFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    return AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.22), colors.textLink.withValues(alpha: 0.08), colors.surfaceDefault],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
        boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 420;
                final nameColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.patientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.h2(context),
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      'with ${detail.doctorDisplayName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                );

                final icon = AnimatedContainer(
                  duration: motionDuration,
                  curve: AppointmentStatusMotion.curve,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: AnimatedAppointmentStatusColor(
                      color: statusColor,
                      builder: (context, color) => Icon(Icons.calendar_month_rounded, color: color, size: 28),
                    ),
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: AppSpacing.space4),
                          Expanded(child: nameColumn),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      _StatusChip(status: detail.status, color: statusColor),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(child: nameColumn),
                    const SizedBox(width: AppSpacing.space2),
                    _StatusChip(status: detail.status, color: statusColor),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.space6),
            Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space2,
              children: [
                _HeroFactChip(icon: Icons.event_outlined, label: dateLabel),
                _HeroFactChip(icon: Icons.schedule_outlined, label: timeLabel),
                _HeroFactChip(icon: Icons.timelapse_outlined, label: durationLabel),
                _HeroFactChip(icon: Icons.category_outlined, label: detail.type.label),
                if (detail.queueNumber != null)
                  _HeroFactChip(icon: Icons.tag_outlined, label: 'Queue #${detail.queueNumber}'),
                _HeroAuditInfoChip(detail: detail, auditFormat: auditFormat),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroAuditInfoChip extends StatefulWidget {
  const _HeroAuditInfoChip({required this.detail, required this.auditFormat});

  final AppointmentDetail detail;
  final DateFormat auditFormat;

  @override
  State<_HeroAuditInfoChip> createState() => _HeroAuditInfoChipState();
}

class _HeroAuditInfoChipState extends State<_HeroAuditInfoChip> {
  var _open = false;
  Timer? _hideTimer;
  var _isButtonHovered = false;
  var _isPopoverHovered = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showPanel() {
    _hideTimer?.cancel();
    setState(() => _open = true);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_isButtonHovered && !_isPopoverHovered && mounted) {
        setState(() => _open = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppPopover(
      open: _open,
      onOpenChange: (value) => setState(() => _open = value),
      align: AppPopoverAlign.center,
      side: AppPopoverSide.top,
      matchTriggerWidth: false,
      minWidth: 220,
      width: 280,
      triggerBuilder: (context, isOpen, onToggle) => MouseRegion(
        onEnter: (_) {
          setState(() => _isButtonHovered = true);
          _showPanel();
        },
        onExit: (_) {
          setState(() => _isButtonHovered = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.help,
        child: GestureDetector(
          onTap: onToggle,
          child: Tooltip(
            message: 'View booking record details',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _isButtonHovered || isOpen ? colors.surfaceMuted : colors.surfaceDefault.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _isButtonHovered || isOpen ? colors.textLink.withValues(alpha: 0.45) : colors.borderDefault,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: colors.textLink),
                    const SizedBox(width: AppSpacing.space1),
                    Text('Record info', style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isPopoverHovered = true);
          _showPanel();
        },
        onExit: (_) {
          setState(() => _isPopoverHovered = false);
          _scheduleHide();
        },
        child: _HeroAuditPanel(detail: widget.detail, auditFormat: widget.auditFormat),
      ),
    );
  }
}

class _HeroAuditPanel extends StatelessWidget {
  const _HeroAuditPanel({required this.detail, required this.auditFormat});

  final AppointmentDetail detail;
  final DateFormat auditFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bookedBy = detail.createdByDisplay?.trim();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space2,
              AppSpacing.space2,
              AppSpacing.space2,
              AppSpacing.space1,
            ),
            child: Text('Record info', style: AppTypography.bodyStrong(context)),
          ),
          _HeroAuditItem(
            icon: Icons.history_rounded,
            label: 'Created',
            value: auditFormat.format(detail.createdAt.toLocal()),
            colors: colors,
          ),
          if (bookedBy != null && bookedBy.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space2),
            _HeroAuditItem(icon: Icons.person_add_alt_1_outlined, label: 'Booked by', value: bookedBy, colors: colors),
          ],
          const SizedBox(height: AppSpacing.space2),
          _HeroAuditItem(
            icon: Icons.update_rounded,
            label: 'Last updated',
            value: auditFormat.format(detail.updatedAt.toLocal()),
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _HeroAuditItem extends StatelessWidget {
  const _HeroAuditItem({required this.icon, required this.label, required this.value, required this.colors});

  final IconData icon;
  final String label;
  final String value;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});

  final AppointmentStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final motionDuration = AppointmentStatusMotion.durationOf(context);

    return AnimatedContainer(
      duration: motionDuration,
      curve: AppointmentStatusMotion.curve,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space1),
        child: AnimatedDefaultTextStyle(
          duration: motionDuration,
          curve: AppointmentStatusMotion.curve,
          style: AppTypography.caption(context).copyWith(color: color, fontWeight: FontWeight.w700),
          child: Text(status.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _HeroFactChip extends StatelessWidget {
  const _HeroFactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.textLink),
            const SizedBox(width: AppSpacing.space1),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentNotesCard extends StatelessWidget {
  const _AppointmentNotesCard({required this.title, required this.body, required this.icon, required this.accent});

  final String title;
  final String body;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: AppSpacing.space2),
                Text(title, style: AppTypography.bodyStrong(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(body, style: AppTypography.body(context)),
          ],
        ),
      ),
    );
  }
}

class _AppointmentDetailScaffold extends StatelessWidget {
  const _AppointmentDetailScaffold({
    required this.title,
    required this.onBack,
    required this.body,
    this.subtitle,
    this.patientId,
    this.headerActions = const [],
  });

  final String title;
  final String? subtitle;
  final String? patientId;
  final List<Widget> headerActions;
  final VoidCallback onBack;
  final Widget body;

  Widget? _buildHeaderActions(BuildContext context) {
    if (headerActions.isEmpty && patientId == null) {
      return null;
    }

    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...headerActions,
        if (patientId != null)
          AppButton(
            variant: AppButtonVariant.primary,
            size: AppButtonSize.md,
            leadingIcon: const Icon(Icons.person_outline),
            onPressed: () => context.nav.pushPatientDetail(patientId!),
            child: const Text('Patient profile'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: title,
          description: subtitle,
          breadcrumb: AppBreadcrumb(
            items: [
              AppBreadcrumbItem(label: 'Calendar', onTap: () => context.nav.goAppointmentsCalendar()),
              AppBreadcrumbItem(label: title),
            ],
          ),
          actions: _buildHeaderActions(context),
        ),
        const SizedBox(height: AppSpacing.space6),
        Expanded(child: SingleChildScrollView(child: body)),
      ],
    );
  }
}

class _AppointmentDetailLoadingView extends StatelessWidget {
  const _AppointmentDetailLoadingView({required this.appointmentId, required this.onBack, this.preview});

  final String appointmentId;
  final AppointmentListItem? preview;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _AppointmentDetailScaffold(
      title: preview?.patientName ?? 'Loading…',
      subtitle: preview?.status.label,
      patientId: preview?.patientId,
      onBack: onBack,
      body: Column(
        children: [
          if (preview != null)
            Opacity(
              opacity: 0.65,
              child: _AppointmentHeroCard(
                detail: _previewAsDetail(preview!),
                statusColor: AppointmentCalendarDisplay.statusColor(preview!.status, Theme.of(context).brightness),
                dateLabel: DateFormat.yMMMEd().format(preview!.startTime.toLocal()),
                timeLabel:
                    '${DateFormat.jm().format(preview!.startTime.toLocal())} – ${DateFormat.jm().format(preview!.endTime.toLocal())}',
                durationLabel: '${preview!.endTime.difference(preview!.startTime).inMinutes} min',
                auditFormat: DateFormat('MMM d, yyyy · h:mm a'),
              ),
            )
          else
            const AppSkeleton(variant: SkeletonVariant.rectangular, height: 180),
          const SizedBox(height: AppSpacing.space6),
          const AppSkeleton(variant: SkeletonVariant.rectangular, height: 220),
          const SizedBox(height: AppSpacing.space6),
          const Center(child: AppProgress(variant: ProgressVariant.circular, indeterminate: true)),
        ],
      ),
    );
  }

  static AppointmentDetail _previewAsDetail(AppointmentListItem preview) {
    final now = DateTime.now().toUtc();
    return AppointmentDetail(
      id: preview.id,
      branchId: '',
      patientId: preview.patientId,
      patientName: preview.patientName,
      doctorId: preview.doctorId,
      doctorName: preview.doctorName,
      startTime: preview.startTime,
      endTime: preview.endTime,
      type: preview.type,
      status: preview.status,
      createdAt: now,
      updatedAt: preview.updatedAt ?? now,
    );
  }
}

class _AppointmentDetailErrorView extends StatelessWidget {
  const _AppointmentDetailErrorView({
    required this.appointmentId,
    required this.message,
    required this.onBack,
    required this.onRetry,
  });

  final String appointmentId;
  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _AppointmentDetailScaffold(
      title: 'Appointment',
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unable to load appointment', style: AppTypography.bodyStrong(context)),
          const SizedBox(height: AppSpacing.space2),
          Text(message, style: AppTypography.bodySm(context).copyWith(color: context.appColors.actionDanger)),
          const SizedBox(height: AppSpacing.space6),
          AppButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AppointmentDetailNotFoundView extends StatelessWidget {
  const _AppointmentDetailNotFoundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _AppointmentDetailScaffold(
      title: 'Appointment not found',
      onBack: onBack,
      body: AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Appointment not found',
        description: 'It may have been removed or you may not have access.',
        action: EmptyStateAction(label: 'Back to calendar', onPressed: onBack),
      ),
    );
  }
}

class _AppointmentDetailPermissionDenied extends StatelessWidget {
  const _AppointmentDetailPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('You do not have permission to view appointments.', style: AppTypography.body(context)));
  }
}
