import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_scale_down_text.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_status_button.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Column 1 — today's appointment schedule with a focus timeline.
class AppointmentQueueScheduleColumn extends ConsumerStatefulWidget {
  const AppointmentQueueScheduleColumn({
    required this.items,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.scrollNonce = 0,
    this.scrollToAppointmentId,
    this.onTargetAppointmentScrollHandled,
    super.key,
  });

  final List<AppointmentListItem> items;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  /// Bumped by the queue page on each visit so the list scrolls to the focused row.
  final int scrollNonce;

  /// When set, scrolls to this appointment instead of the slot closest to [now].
  final String? scrollToAppointmentId;

  /// Called after a requested [scrollToAppointmentId] scroll completes.
  final VoidCallback? onTargetAppointmentScrollHandled;

  static const flashDuration = Duration(milliseconds: 1400);

  @override
  ConsumerState<AppointmentQueueScheduleColumn> createState() => _AppointmentQueueScheduleColumnState();
}

class _AppointmentQueueScheduleColumnState extends ConsumerState<AppointmentQueueScheduleColumn> {
  static final _timeFormat = DateFormat('h:mm a');
  static final _dateFormat = DateFormat('MMM d, yyyy');
  static const _focusBubbleColor = Color(0xFF14B8A6);
  static const _timelineGutterWidth = 28.0;
  static const _timelineBubbleSize = 12.0;
  static const _timelineLineWidth = 2.0;
  static const _rowGap = SpacingTokens.sm;
  static const _estimatedRowHeight = 92.0;
  static const _maxScrollAttempts = 16;

  final _scrollTargetRowKey = GlobalKey();
  final _scrollController = ScrollController();
  String? _lastSuccessfulScrollKey;
  String? _pendingScrollKey;
  String? _flashingAppointmentId;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToCurrent();
  }

  @override
  void didUpdateWidget(covariant AppointmentQueueScheduleColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToAppointmentId != null &&
        oldWidget.scrollToAppointmentId!.isNotEmpty &&
        widget.scrollToAppointmentId == null) {
      _lastSuccessfulScrollKey = _scrollKey();
    }
    _scheduleScrollToCurrent();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String _scrollKey() {
    final itemSignature = widget.items.map((item) => item.id).join(',');
    return '${widget.scrollNonce}|${widget.scrollToAppointmentId ?? ''}|$itemSignature';
  }

  int _scrollTargetIndex() {
    final targetId = widget.scrollToAppointmentId;
    if (targetId != null && targetId.isNotEmpty) {
      final index = widget.items.indexWhere((item) => item.id == targetId);
      if (index >= 0) {
        return index;
      }
    }
    return AppointmentQueueDisplay.indexClosestToNow(widget.items, now: widget.now);
  }

  void _triggerFlash(String appointmentId) {
    _flashTimer?.cancel();
    setState(() => _flashingAppointmentId = appointmentId);
    _flashTimer = Timer(AppointmentQueueScheduleColumn.flashDuration, () {
      if (!mounted) {
        return;
      }
      setState(() => _flashingAppointmentId = null);
      widget.onTargetAppointmentScrollHandled?.call();
    });
  }

  void _scheduleScrollToCurrent() {
    if (widget.items.isEmpty) {
      return;
    }

    final scrollKey = _scrollKey();
    if (_lastSuccessfulScrollKey == scrollKey) {
      return;
    }

    _pendingScrollKey = scrollKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptScrollToFocused(0));
  }

  void _attemptScrollToFocused(int attempt) {
    if (!mounted || _pendingScrollKey == null) {
      return;
    }

    final closestIndex = _scrollTargetIndex();
    if (_scrollController.hasClients && _scrollTargetRowKey.currentContext == null) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = (closestIndex * _estimatedRowHeight).clamp(0.0, maxExtent);
      _scrollController.jumpTo(targetOffset);
    }

    final rowContext = _scrollTargetRowKey.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
      _lastSuccessfulScrollKey = _pendingScrollKey;
      final flashId = widget.scrollToAppointmentId;
      if (flashId != null && flashId.isNotEmpty) {
        _triggerFlash(flashId);
      }
      _pendingScrollKey = null;
      return;
    }

    if (attempt < _maxScrollAttempts) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _attemptScrollToFocused(attempt + 1));
      return;
    }

    _pendingScrollKey = null;
  }

  String _timeRangeLabel(AppointmentListItem item) {
    final start = _timeFormat.format(item.startTime.toLocal());
    if (item.status != AppointmentStatus.completed) {
      return start;
    }
    final end = _timeFormat.format(item.endTime.toLocal());
    return '$start - $end';
  }

  Future<void> _showBookingSheet({required String branchId, required BranchWorkingSchedule schedule}) async {
    final doctors = ref.read(appointmentCalendarDoctorsProvider).value ?? const <StaffListItem>[];
    final slotRange = AppointmentCalendarDisplay.slotRangeFromTap(
      tappedDate: AppointmentCalendarDisplay.snapTimeToSlot(widget.now),
      schedule: schedule,
      mode: AppointmentCalendarMode.day,
    );

    final booked = await AppointmentBookingSheet.show(
      context,
      branchId: branchId,
      schedule: schedule,
      slotStart: slotRange.start,
      slotEnd: slotRange.end,
      doctors: doctors,
    );
    if (booked == true && mounted) {
      await ref.read(appointmentQueueProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final closestIndex = AppointmentQueueDisplay.indexClosestToNow(widget.items, now: widget.now);
    final scrollTargetIndex = _scrollTargetIndex();

    final dateLabel = _dateFormat.format(widget.now.toLocal());
    final canCreate = ref.watch(permissionServiceProvider).canCreateAppointments();
    final branchId = ref.watch(authSessionProvider).context?.activeBranchId?.trim();
    final branches = ref.watch(appointmentCalendarBranchesProvider).value ?? const <BranchListItem>[];
    final selectedBranch = branches.where((branch) => branch.id == branchId).firstOrNull;
    final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
    final canBook = canCreate && branchId != null && branchId.isNotEmpty;

    return AppNotchedCard(
      titleIcon: Icons.event_note_outlined,
      title: Text(
        'Appointments',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      actions: [
        if (canBook)
          AppNotchedCardAction(
            providesOwnBackground: true,
            action: AppButton(
              label: 'Book Appointment',
              size: AppFieldSize.sm,
              onPressed: () => unawaited(_showBookingSheet(branchId: branchId, schedule: schedule)),
            ),
          ),
        AppBadge(label: dateLabel, variant: AppBadgeVariant.plain),
        AppIconButton(
          icon: Icon(Icons.calendar_today_outlined, color: colors.primary),
          tooltip: 'Open calendar',
          onPressed: () => AppNavigator(context).goAppointmentsCalendar(),
        ),
      ],
      body: widget.items.isEmpty
          ? const _ScheduleEmptyState()
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final isFocused = index == closestIndex;
                final isScrollTarget = index == scrollTargetIndex;
                final isPast = index < closestIndex;
                return _ScheduleTimelineRow(
                  key: isScrollTarget ? _scrollTargetRowKey : ValueKey(item.id),
                  isFirst: index == 0,
                  isLast: index == widget.items.length - 1,
                  isPast: isPast,
                  isFocused: isFocused,
                  activeLineColor: colors.primary,
                  inactiveLineColor: colors.border,
                  focusBubbleColor: _focusBubbleColor,
                  inactiveBubbleColor: colors.mutedForeground.withValues(alpha: 0.45),
                  gutterWidth: _timelineGutterWidth,
                  bubbleSize: _timelineBubbleSize,
                  lineWidth: _timelineLineWidth,
                  bottomGap: index < widget.items.length - 1 ? _rowGap : 0,
                  child: _AppointmentRow(
                    item: item,
                    shiftLookup: widget.shiftLookup,
                    timeLabel: _timeRangeLabel(item),
                    isFocused: isFocused,
                    isFlashing: _flashingAppointmentId == item.id,
                    statusDimmed: AppointmentQueueDisplay.isScheduleRowDimmed(item),
                    now: widget.now,
                    onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
                  ),
                );
              },
            ),
    );
  }
}

class _AppointmentRow extends StatefulWidget {
  const _AppointmentRow({
    required this.item,
    required this.shiftLookup,
    required this.timeLabel,
    required this.isFocused,
    required this.isFlashing,
    required this.statusDimmed,
    required this.now,
    required this.onTap,
  });

  final AppointmentListItem item;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final String timeLabel;
  final bool isFocused;
  final bool isFlashing;
  final bool statusDimmed;
  final DateTime now;
  final VoidCallback onTap;

  @override
  State<_AppointmentRow> createState() => _AppointmentRowState();
}

class _AppointmentRowState extends State<_AppointmentRow> with SingleTickerProviderStateMixin {
  late AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: AppointmentQueueScheduleColumn.flashDuration,
      value: 1,
    );
    if (widget.isFlashing) {
      _flashController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _AppointmentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFlashing && !oldWidget.isFlashing) {
      _flashController.forward(from: 0);
    } else if (!widget.isFlashing && oldWidget.isFlashing) {
      _flashController.value = 1;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = item.status == AppointmentStatus.noShow
        ? colors.destructive
        : AppointmentCalendarDisplay.statusColor(item.status);
    final opacity = widget.statusDimmed ? 0.5 : 1.0;
    final primaryTextColor = widget.isFocused ? colors.foreground : colors.mutedForeground;
    final primaryWeight = widget.isFocused ? FontWeight.w700 : FontWeight.w500;
    final showWait = item.status == AppointmentStatus.checkedIn;
    final waitLabel = showWait
        ? AppointmentQueueDisplay.formatWaitedLabel(AppointmentQueueDisplay.estimateWaitDuration(item, now: widget.now))
        : null;

    final doctorPresentation = AppointmentQueueDisplay.queueDoctorPresentation(item, shiftLookup: widget.shiftLookup);
    final visitLabel = _doctorVisitLabel(item);
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    return Opacity(
      opacity: opacity,
      child: AnimatedBuilder(
        animation: _flashController,
        builder: (context, child) {
          final glow = (1 - Curves.easeOut.transform(_flashController.value)).clamp(0.0, 1.0);
          final borderColor = Color.lerp(colors.border, colors.primary, glow * 0.95)!;
          return FCard.raw(
            style: FCardStyleDelta.delta(
              decoration: DecorationDelta.boxDelta(
                color: colors.card,
                border: Border.all(color: borderColor, width: 1 + glow * 2),
                borderRadius: borderRadius,
                boxShadow: glow > 0.05
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: glow * 0.35),
                          blurRadius: 8 + glow * 6,
                        ),
                      ]
                    : null,
              ),
            ),
            child: child!,
          );
        },
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor.withValues(alpha: 0.22), statusColor.withValues(alpha: 0)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.schedule_outlined,
                          minIconSize: 60,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.timeLabel,
                                style: textTheme.titleSmall?.copyWith(
                                  color: primaryTextColor,
                                  fontWeight: primaryWeight,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.status.label,
                                style: textTheme.bodySmall?.copyWith(
                                  color: primaryTextColor,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _QueueSectionDivider(color: colors.border),
                      Expanded(
                        flex: 3,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.assignment_ind_outlined,
                          child: _PersonColumn(
                            name: item.patientName,
                            subtitle: item.type.label,
                            waitLabel: waitLabel,
                            primaryTextColor: primaryTextColor,
                          ),
                        ),
                      ),
                      _QueueSectionDivider(color: colors.border),
                      Expanded(
                        flex: 3,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.medical_services_outlined,
                          child: _QueueDoctorColumn(
                            presentation: doctorPresentation,
                            visitLabel: visitLabel,
                            primaryTextColor: primaryTextColor,
                          ),
                        ),
                      ),
                      _QueueSectionDivider(color: colors.border),
                      Padding(
                        padding: const EdgeInsets.only(top: SpacingTokens.xs),
                        child: AppointmentQueueRowStatusButton(item: item),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _doctorVisitLabel(AppointmentListItem item) {
    return switch (item.status) {
      AppointmentStatus.inProgress => 'In consultation',
      AppointmentStatus.completed => 'Completed visit',
      _ => 'Consultation',
    };
  }
}

class _QueueDoctorColumn extends StatelessWidget {
  const _QueueDoctorColumn({required this.presentation, required this.visitLabel, required this.primaryTextColor});

  final QueueAppointmentDoctorPresentation presentation;
  final String visitLabel;
  final Color primaryTextColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final names = presentation.displayNames;
    final subtitle = presentation.hasPatientChoice ? "Patient's choice · $visitLabel" : visitLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppointmentScaleDownText(
          text: names,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: primaryTextColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PersonColumn extends StatelessWidget {
  const _PersonColumn({required this.name, required this.subtitle, required this.primaryTextColor, this.waitLabel});

  final String name;
  final String subtitle;
  final String? waitLabel;
  final Color primaryTextColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final subtitleStyle = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppointmentScaleDownText(
          text: name,
          style: textTheme.bodyMedium?.copyWith(color: primaryTextColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(subtitle, style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (waitLabel != null) ...[
              Text(' · ', style: subtitleStyle),
              Flexible(
                child: Text(waitLabel!, style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Centered vertical divider between queue appointment row sections.
class _QueueSectionDivider extends StatelessWidget {
  const _QueueSectionDivider({required this.color});

  final Color color;

  static const _gap = SpacingTokens.md;
  static const _lineHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gap * 2 + 1,
      child: Center(
        child: SizedBox(
          height: _lineHeight,
          child: VerticalDivider(width: 1, thickness: 1, color: color.withValues(alpha: 1)),
        ),
      ),
    );
  }
}

class _ScheduleTimelineRow extends StatefulWidget {
  const _ScheduleTimelineRow({
    required this.isFirst,
    required this.isLast,
    required this.isPast,
    required this.isFocused,
    required this.activeLineColor,
    required this.inactiveLineColor,
    required this.focusBubbleColor,
    required this.inactiveBubbleColor,
    required this.gutterWidth,
    required this.bubbleSize,
    required this.lineWidth,
    required this.bottomGap,
    required this.child,
    super.key,
  });

  final bool isFirst;
  final bool isLast;
  final bool isPast;
  final bool isFocused;
  final Color activeLineColor;
  final Color inactiveLineColor;
  final Color focusBubbleColor;
  final Color inactiveBubbleColor;
  final double gutterWidth;
  final double bubbleSize;
  final double lineWidth;
  final double bottomGap;
  final Widget child;

  @override
  State<_ScheduleTimelineRow> createState() => _ScheduleTimelineRowState();
}

class _ScheduleTimelineRowState extends State<_ScheduleTimelineRow> {
  final _cardKey = GlobalKey();
  var _cardHeight = 72.0;

  bool get _isSingle => widget.isFirst && widget.isLast;

  bool get _showLineAbove => _isSingle || !widget.isFirst;

  bool get _showLineBelow => _isSingle || !widget.isLast;

  Color get _lineAboveColor => widget.isPast || widget.isFocused ? widget.activeLineColor : widget.inactiveLineColor;

  Color get _lineBelowColor => widget.isPast && !widget.isFocused ? widget.activeLineColor : widget.inactiveLineColor;

  Color get _bubbleRingColor {
    if (widget.isFocused) {
      return widget.focusBubbleColor;
    }
    if (widget.isPast) {
      return widget.activeLineColor;
    }
    return widget.inactiveBubbleColor;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_syncCardHeight);
  }

  @override
  void didUpdateWidget(covariant _ScheduleTimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_syncCardHeight);
  }

  void _syncCardHeight(_) {
    if (!mounted) {
      return;
    }

    final height = _cardKey.currentContext?.size?.height;
    if (height == null || height <= 0 || (_cardHeight - height).abs() < 0.5) {
      return;
    }

    setState(() => _cardHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final gutterHeight = _cardHeight + widget.bottomGap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: widget.gutterWidth,
            height: gutterHeight,
            child: CustomPaint(
              painter: _QueueTimelineGutterPainter(
                lineAboveColor: _lineAboveColor,
                lineBelowColor: _lineBelowColor,
                lineWidth: widget.lineWidth,
                bubbleSize: widget.bubbleSize,
                bubbleRingColor: _bubbleRingColor,
                bubbleCenterColor: colors.card,
                showLineAbove: _showLineAbove,
                showLineBelow: _showLineBelow,
                cardHeight: _cardHeight,
              ),
            ),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.bottomGap),
            child: KeyedSubtree(key: _cardKey, child: widget.child),
          ),
        ),
      ],
    );
  }
}

class _QueueTimelineGutterPainter extends CustomPainter {
  const _QueueTimelineGutterPainter({
    required this.lineAboveColor,
    required this.lineBelowColor,
    required this.lineWidth,
    required this.bubbleSize,
    required this.bubbleRingColor,
    required this.bubbleCenterColor,
    required this.showLineAbove,
    required this.showLineBelow,
    required this.cardHeight,
  });

  final Color lineAboveColor;
  final Color lineBelowColor;
  final double lineWidth;
  final double bubbleSize;
  final Color bubbleRingColor;
  final Color bubbleCenterColor;
  final bool showLineAbove;
  final bool showLineBelow;
  final double cardHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final bubbleCenterY = cardHeight / 2;
    final center = Offset(size.width / 2, bubbleCenterY);
    final bubbleRadius = bubbleSize / 2;

    if (showLineAbove) {
      canvas.drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, center.dy - bubbleRadius),
        Paint()
          ..color = lineAboveColor
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round,
      );
    }
    if (showLineBelow) {
      canvas.drawLine(
        Offset(center.dx, center.dy + bubbleRadius),
        Offset(center.dx, size.height),
        Paint()
          ..color = lineBelowColor
          ..strokeWidth = lineWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(center, bubbleRadius, Paint()..color = bubbleCenterColor);
    canvas.drawCircle(
      center,
      bubbleRadius,
      Paint()
        ..color = bubbleRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _QueueTimelineGutterPainter oldDelegate) {
    return lineAboveColor != oldDelegate.lineAboveColor ||
        lineBelowColor != oldDelegate.lineBelowColor ||
        lineWidth != oldDelegate.lineWidth ||
        bubbleSize != oldDelegate.bubbleSize ||
        bubbleRingColor != oldDelegate.bubbleRingColor ||
        bubbleCenterColor != oldDelegate.bubbleCenterColor ||
        showLineAbove != oldDelegate.showLineAbove ||
        showLineBelow != oldDelegate.showLineBelow ||
        cardHeight != oldDelegate.cardHeight;
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined, size: 40, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text(
              'No appointments today',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              'Booked visits will appear here in time order.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
