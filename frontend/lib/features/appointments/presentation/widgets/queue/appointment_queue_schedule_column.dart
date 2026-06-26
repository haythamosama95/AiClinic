import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/tilted_background_icon_stack.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_scale_down_text.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_advance_button.dart';

/// Column 1 — today's appointment schedule with a focus timeline.
class AppointmentQueueScheduleColumn extends StatefulWidget {
  const AppointmentQueueScheduleColumn({
    required this.items,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.scrollNonce = 0,
    super.key,
  });

  final List<AppointmentListItem> items;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  /// Bumped by the queue page on each visit so the list scrolls to the focused row.
  final int scrollNonce;

  @override
  State<AppointmentQueueScheduleColumn> createState() => _AppointmentQueueScheduleColumnState();
}

class _AppointmentQueueScheduleColumnState extends State<AppointmentQueueScheduleColumn> {
  static final _timeFormat = DateFormat('h:mm a');
  static final _dateFormat = DateFormat('MMM d, yyyy');
  static const _focusBubbleColor = Color(0xFF14B8A6);
  static const _timelineGutterWidth = 28.0;
  static const _timelineBubbleSize = 12.0;
  static const _timelineLineWidth = 2.0;
  static const _rowGap = SpacingTokens.sm;
  static const _estimatedRowHeight = 92.0;
  static const _maxScrollAttempts = 16;

  final _closestRowKey = GlobalKey();
  final _scrollController = ScrollController();
  String? _lastSuccessfulScrollKey;
  String? _pendingScrollKey;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToCurrent();
  }

  @override
  void didUpdateWidget(covariant AppointmentQueueScheduleColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollToCurrent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _scrollKey() {
    final itemSignature = widget.items.map((item) => item.id).join(',');
    return '${widget.scrollNonce}|$itemSignature';
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

    final closestIndex = AppointmentQueueDisplay.indexClosestToNow(widget.items, now: widget.now);
    if (_scrollController.hasClients && _closestRowKey.currentContext == null) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = (closestIndex * _estimatedRowHeight).clamp(0.0, maxExtent);
      _scrollController.jumpTo(targetOffset);
    }

    final rowContext = _closestRowKey.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _lastSuccessfulScrollKey = _pendingScrollKey;
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

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final closestIndex = AppointmentQueueDisplay.indexClosestToNow(widget.items, now: widget.now);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppointmentsHeader(
            dateLabel: _dateFormat.format(widget.now.toLocal()),
            onOpenCalendar: () => AppNavigator(context).goAppointmentsCalendar(),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.items.isEmpty
                ? const _ScheduleEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isFocused = index == closestIndex;
                      final isPast = index < closestIndex;
                      return _ScheduleTimelineRow(
                        key: isFocused ? _closestRowKey : ValueKey(item.id),
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
                          siblingAppointments: widget.items,
                          timeLabel: _timeRangeLabel(item),
                          isFocused: isFocused,
                          statusDimmed: AppointmentQueueDisplay.isScheduleRowDimmed(item),
                          now: widget.now,
                          onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsHeader extends StatelessWidget {
  const _AppointmentsHeader({required this.dateLabel, required this.onOpenCalendar});

  final String dateLabel;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
      child: Row(
        children: [
          Text('Appointments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(dateLabel, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground)),
          const SizedBox(width: SpacingTokens.xs),
          _HeaderIconButton(icon: Icons.chevron_left, tooltip: 'Previous day', onPressed: onOpenCalendar),
          _HeaderIconButton(icon: Icons.chevron_right, tooltip: 'Next day', onPressed: onOpenCalendar),
          _HeaderIconButton(
            icon: Icons.calendar_today_outlined,
            tooltip: 'Open calendar',
            iconColor: colors.primary,
            onPressed: onOpenCalendar,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip, required this.onPressed, this.iconColor});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: iconColor ?? colors.mutedForeground),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.item,
    required this.shiftLookup,
    required this.siblingAppointments,
    required this.timeLabel,
    required this.isFocused,
    required this.statusDimmed,
    required this.now,
    required this.onTap,
  });

  final AppointmentListItem item;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final List<AppointmentListItem> siblingAppointments;
  final String timeLabel;
  final bool isFocused;
  final bool statusDimmed;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = AppointmentCalendarDisplay.statusColor(item.status);
    final opacity = statusDimmed ? 0.5 : 1.0;
    final primaryTextColor = isFocused ? colors.foreground : colors.mutedForeground;
    final primaryWeight = isFocused ? FontWeight.w700 : FontWeight.w500;
    final showWait = item.status == AppointmentStatus.checkedIn;
    final waitLabel = showWait
        ? AppointmentQueueDisplay.formatWaitedLabel(AppointmentQueueDisplay.estimateWaitDuration(item, now: now))
        : null;

    final doctorPresentation = AppointmentQueueDisplay.queueDoctorPresentation(item, shiftLookup: shiftLookup);
    final visitLabel = _doctorVisitLabel(item);
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    return Opacity(
      opacity: opacity,
      child: FCard.raw(
        style: FCardStyleDelta.delta(
          decoration: DecorationDelta.boxDelta(
            color: colors.card,
            border: Border.all(color: colors.border),
            borderRadius: borderRadius,
          ),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
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
                        width: 100,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.schedule_outlined,
                          minIconSize: 88,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeLabel,
                                style: textTheme.titleSmall?.copyWith(
                                  color: primaryTextColor,
                                  fontWeight: primaryWeight,
                                ),
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
                      _RowDivider(color: colors.border),
                      Expanded(
                        flex: 3,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.assignment_ind_outlined,
                          child: _PersonColumn(
                            name: item.patientName,
                            subtitle: item.type.label,
                            waitLabel: waitLabel,
                            primaryTextColor: primaryTextColor,
                            primaryWeight: primaryWeight,
                          ),
                        ),
                      ),
                      _RowDivider(color: colors.border),
                      Expanded(
                        flex: 3,
                        child: TiltedBackgroundIconStack(
                          icon: Icons.medical_services_outlined,
                          child: _QueueDoctorColumn(
                            presentation: doctorPresentation,
                            visitLabel: visitLabel,
                            primaryTextColor: primaryTextColor,
                            primaryWeight: primaryWeight,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: SpacingTokens.xs),
                        child: AppointmentQueueRowAdvanceButton(
                          item: item,
                          siblingAppointments: siblingAppointments,
                          shiftLookup: shiftLookup,
                        ),
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
  const _QueueDoctorColumn({
    required this.presentation,
    required this.visitLabel,
    required this.primaryTextColor,
    required this.primaryWeight,
  });

  final QueueAppointmentDoctorPresentation presentation;
  final String visitLabel;
  final Color primaryTextColor;
  final FontWeight primaryWeight;

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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: primaryTextColor, fontWeight: primaryWeight),
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
  const _PersonColumn({
    required this.name,
    required this.subtitle,
    required this.primaryTextColor,
    required this.primaryWeight,
    this.waitLabel,
  });

  final String name;
  final String subtitle;
  final String? waitLabel;
  final Color primaryTextColor;
  final FontWeight primaryWeight;

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
          style: textTheme.bodyMedium?.copyWith(color: primaryTextColor, fontWeight: primaryWeight),
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

class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      color: color.withValues(alpha: 0.65),
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
