import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_detail_controls_card.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_timeline_widget.dart';

/// Full appointment profile page loaded via `get_appointment`.
class AppointmentDetailPage extends ConsumerWidget {
  const AppointmentDetailPage({required this.appointmentId, this.preview, super.key});

  final String appointmentId;
  final AppointmentListItem? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const _AppointmentDetailPermissionDenied();
    }

    final detailAsync = ref.watch(appointmentDetailProvider(appointmentId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () =>
          _AppointmentDetailLoadingView(appointmentId: appointmentId, preview: preview, onBack: () => _goBack(context)),
      error: (error, _) => _AppointmentDetailErrorView(
        appointmentId: appointmentId,
        message: error.toString(),
        onBack: () => _goBack(context),
        onRetry: () => ref.invalidate(appointmentDetailProvider(appointmentId)),
      ),
      data: (detail) => _AppointmentDetailContentView(detail: detail, onBack: () => _goBack(context)),
    );
  }

  static void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goAppointmentsCalendar();
  }
}

class _AppointmentDetailContentView extends StatelessWidget {
  const _AppointmentDetailContentView({required this.detail, required this.onBack});

  final AppointmentDetail detail;
  final VoidCallback onBack;

  static final _dateFormat = DateFormat('EEEE, MMM d, yyyy');
  static final _timeFormat = DateFormat('h:mm a');
  static final _auditFormat = DateFormat('MMM d, yyyy · h:mm a');

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final statusColor = AppointmentCalendarDisplay.statusColor(detail.status);
    final durationMinutes = detail.endTime.difference(detail.startTime).inMinutes;

    return _AppointmentDetailScaffold(
      title: detail.patientName,
      subtitle: detail.status.label,
      patientId: detail.patientId,
      onBack: onBack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useSideControls = constraints.maxWidth >= 720;
          final heroCard = _AppointmentHeroCard(
            detail: detail,
            statusColor: statusColor,
            dateLabel: _dateFormat.format(detail.startTime.toLocal()),
            timeLabel:
                '${_timeFormat.format(detail.startTime.toLocal())} – ${_timeFormat.format(detail.endTime.toLocal())}',
            durationLabel: '$durationMinutes min',
            auditFormat: _auditFormat,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (useSideControls)
                _AppointmentDetailHeroControlsRow(heroCard: heroCard, detail: detail)
              else ...[
                heroCard,
                const SizedBox(height: SpacingTokens.md),
                AppointmentDetailControlsCard(detail: detail),
              ],
              const SizedBox(height: SpacingTokens.lg),
              AppointmentStatusTimelineWidget(currentStatus: detail.status),
              if (detail.notes?.trim().isNotEmpty == true || detail.cancelReason?.trim().isNotEmpty == true) ...[
                const SizedBox(height: SpacingTokens.lg),
                if (detail.notes?.trim().isNotEmpty == true)
                  _AppointmentNotesCard(
                    title: 'Notes',
                    body: detail.notes!.trim(),
                    icon: Icons.sticky_note_2_outlined,
                    accent: colors.primary,
                  ),
                if (detail.cancelReason?.trim().isNotEmpty == true) ...[
                  if (detail.notes?.trim().isNotEmpty == true) const SizedBox(height: SpacingTokens.md),
                  _AppointmentNotesCard(
                    title: 'Cancellation reason',
                    body: detail.cancelReason!.trim(),
                    icon: Icons.info_outline_rounded,
                    accent: colors.destructive,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Side-by-side hero and manage cards where manage never exceeds hero height.
class _AppointmentDetailHeroControlsRow extends StatefulWidget {
  const _AppointmentDetailHeroControlsRow({required this.heroCard, required this.detail});

  final Widget heroCard;
  final AppointmentDetail detail;

  @override
  State<_AppointmentDetailHeroControlsRow> createState() => _AppointmentDetailHeroControlsRowState();
}

class _AppointmentDetailHeroControlsRowState extends State<_AppointmentDetailHeroControlsRow> {
  final _heroKey = GlobalKey();
  double? _heroHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeroHeight());
  }

  @override
  void didUpdateWidget(covariant _AppointmentDetailHeroControlsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeroHeight());
  }

  void _syncHeroHeight() {
    if (!mounted) {
      return;
    }

    final height = _heroKey.currentContext?.size?.height;
    if (height != null && height > 0 && height != _heroHeight) {
      setState(() => _heroHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: KeyedSubtree(key: _heroKey, child: widget.heroCard),
        ),
        const SizedBox(width: SpacingTokens.lg),
        SizedBox(
          width: 272,
          child: AppointmentDetailControlsCard(detail: widget.detail, maxHeight: _heroHeight),
        ),
      ],
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
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.22), colors.primary.withValues(alpha: 0.08), colors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
        boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(context.shapeTokens.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Icon(Icons.calendar_month_rounded, color: statusColor, size: 28),
                  ),
                ),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.patientName,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        'with ${detail.doctorDisplayName}',
                        style: theme.textTheme.titleMedium?.copyWith(color: colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: detail.status, color: statusColor),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            Wrap(
              spacing: SpacingTokens.md,
              runSpacing: SpacingTokens.sm,
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

final _auditPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 150),
    exitDuration: Duration(milliseconds: 100),
    scaleTween: Tween<double>(begin: 0.96, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

class _HeroAuditInfoChip extends StatefulWidget {
  const _HeroAuditInfoChip({required this.detail, required this.auditFormat});

  final AppointmentDetail detail;
  final DateFormat auditFormat;

  @override
  State<_HeroAuditInfoChip> createState() => _HeroAuditInfoChipState();
}

class _HeroAuditInfoChipState extends State<_HeroAuditInfoChip> with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  Timer? _hideTimer;
  var _isButtonHovered = false;
  var _isPopoverHovered = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showPanel() {
    _hideTimer?.cancel();
    _controller.show();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!_isButtonHovered && !_isPopoverHovered) {
        _controller.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _auditPopoverMotion,
      hideRegion: FPopoverHideRegion.none,
      constraints: const FPortalConstraints(minWidth: 220, maxWidth: 280),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) => MouseRegion(
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
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) {
          setState(() => _isButtonHovered = true);
          _showPanel();
        },
        onExit: (_) {
          setState(() => _isButtonHovered = false);
          _scheduleHide();
        },
        cursor: SystemMouseCursors.help,
        child: FTappable(
          onPress: controller.toggle,
          child: IgnorePointer(child: child),
        ),
      ),
      child: Tooltip(
        message: 'View booking record details',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _isButtonHovered ? colors.muted : colors.card.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _isButtonHovered ? colors.primary.withValues(alpha: 0.45) : colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: colors.primary),
                const SizedBox(width: SpacingTokens.xs),
                Text(
                  'Record info',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
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
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final bookedBy = detail.createdByDisplay?.trim();

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.xs),
            child: Text('Record info', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          _HeroAuditItem(
            icon: Icons.history_rounded,
            label: 'Created',
            value: auditFormat.format(detail.createdAt.toLocal()),
            colors: colors,
            textTheme: theme.textTheme,
          ),
          if (bookedBy != null && bookedBy.isNotEmpty) ...[
            const SizedBox(height: SpacingTokens.sm),
            _HeroAuditItem(
              icon: Icons.person_add_alt_1_outlined,
              label: 'Booked by',
              value: bookedBy,
              colors: colors,
              textTheme: theme.textTheme,
            ),
          ],
          const SizedBox(height: SpacingTokens.sm),
          _HeroAuditItem(
            icon: Icons.update_rounded,
            label: 'Last updated',
            value: auditFormat.format(detail.updatedAt.toLocal()),
            colors: colors,
            textTheme: theme.textTheme,
          ),
        ],
      ),
    );
  }
}

class _HeroAuditItem extends StatelessWidget {
  const _HeroAuditItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    required this.textTheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final SemanticColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.mutedForeground),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
                const SizedBox(height: 2),
                Text(value, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.xs),
        child: Text(
          status.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
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
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.primary),
            const SizedBox(width: SpacingTokens.xs),
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
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
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: SpacingTokens.sm),
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
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
  });

  final String title;
  final String? subtitle;
  final String? patientId;
  final VoidCallback onBack;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIconButton(icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back', onPressed: onBack),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appointment',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                      ),
                  ],
                ),
              ),
              if (patientId != null) ...[
                const SizedBox(width: SpacingTokens.sm),
                AppButton(
                  label: 'Patient profile',
                  variant: AppButtonVariant.ghost,
                  size: AppFieldSize.sm,
                  icon: const Icon(Icons.person_outline, size: 18),
                  onPressed: () => context.nav.pushPatientDetail(patientId!),
                ),
              ],
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(child: SingleChildScrollView(child: body)),
        ],
      ),
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
                statusColor: AppointmentCalendarDisplay.statusColor(preview!.status),
                dateLabel: DateFormat.yMMMEd().format(preview!.startTime.toLocal()),
                timeLabel:
                    '${DateFormat.jm().format(preview!.startTime.toLocal())} – ${DateFormat.jm().format(preview!.endTime.toLocal())}',
                durationLabel: '${preview!.endTime.difference(preview!.startTime).inMinutes} min',
                auditFormat: DateFormat('MMM d, yyyy · h:mm a'),
              ),
            )
          else
            const AppSkeletonBox(height: 180),
          const SizedBox(height: SpacingTokens.lg),
          const AppSkeletonBox(height: 220),
          const SizedBox(height: SpacingTokens.lg),
          const Center(child: AppCircularProgress()),
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
      updatedAt: now,
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
    final colors = context.semanticColors;

    return _AppointmentDetailScaffold(
      title: 'Appointment',
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unable to load appointment', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SpacingTokens.sm),
          Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive)),
          const SizedBox(height: SpacingTokens.lg),
          AppButton(label: 'Retry', expand: false, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _AppointmentDetailPermissionDenied extends StatelessWidget {
  const _AppointmentDetailPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('You do not have permission to view appointments.'));
  }
}
