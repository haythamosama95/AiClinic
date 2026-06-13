import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Past visits or upcoming appointments with a single-select tab control.
class PatientDetailTimelineSection extends ConsumerStatefulWidget {
  const PatientDetailTimelineSection({
    required this.patientId,
    required this.pastVisits,
    required this.upcomingAppointments,
    this.patientBranchName,
    this.pastLoading = false,
    this.upcomingLoading = false,
    this.pastError,
    this.upcomingError,
    this.onRetryPast,
    this.onRetryUpcoming,
    super.key,
  });

  final String patientId;
  final List<VisitListItem> pastVisits;
  final List<AppointmentListItem> upcomingAppointments;
  final String? patientBranchName;
  final bool pastLoading;
  final bool upcomingLoading;
  final String? pastError;
  final String? upcomingError;
  final VoidCallback? onRetryPast;
  final VoidCallback? onRetryUpcoming;

  static final _timelineDate = DateFormat('d MMM \'yy');
  static final _timelineTime = DateFormat('HH.mm');

  @override
  ConsumerState<PatientDetailTimelineSection> createState() => _PatientDetailTimelineSectionState();
}

class _PatientDetailTimelineSectionState extends ConsumerState<PatientDetailTimelineSection> {
  static const _tabTransitionDuration = Duration(milliseconds: 220);

  var _tabTransitionDirection = 0;

  void _onTabSelected(PatientDetailHistoryTab tab) {
    final current = ref.read(patientDetailHistoryTabProvider(widget.patientId));
    if (current == tab) {
      return;
    }

    setState(() {
      _tabTransitionDirection = tab.index >= current.index ? 1 : -1;
    });
    ref.read(patientDetailHistoryTabProvider(widget.patientId).notifier).select(tab);
  }

  Widget _panelFor(PatientDetailHistoryTab tab) {
    return switch (tab) {
      PatientDetailHistoryTab.past => _TimelinePanelContent(
        isLoading: widget.pastLoading,
        error: widget.pastError,
        onRetry: widget.onRetryPast,
        child: widget.pastVisits.isEmpty && !widget.pastLoading && widget.pastError == null
            ? const _TimelineEmptyState(message: 'No past visits recorded.')
            : _VisitsTimeline(
                items: [
                  for (final visit in widget.pastVisits)
                    _VisitTimelineItem(
                      dateLabel: PatientDetailTimelineSection._timelineDate.format(visit.visitDate),
                      timeLabel: PatientDetailTimelineSection._timelineTime.format(visit.visitDate),
                      branch: visit.branchName,
                      doctorName: visit.doctorName,
                      state: visit.status.label,
                    ),
                ],
              ),
      ),
      PatientDetailHistoryTab.upcoming => _TimelinePanelContent(
        isLoading: widget.upcomingLoading,
        error: widget.upcomingError,
        onRetry: widget.onRetryUpcoming,
        child: widget.upcomingAppointments.isEmpty && !widget.upcomingLoading && widget.upcomingError == null
            ? const _TimelineEmptyState(message: 'No upcoming appointments scheduled.')
            : _VisitsTimeline(
                items: [
                  for (final appointment in widget.upcomingAppointments)
                    _VisitTimelineItem(
                      dateLabel: PatientDetailTimelineSection._timelineDate.format(appointment.startTime.toLocal()),
                      timeLabel:
                          '${PatientDetailTimelineSection._timelineTime.format(appointment.startTime.toLocal())} - ${PatientDetailTimelineSection._timelineTime.format(appointment.endTime.toLocal())}',
                      branch: widget.patientBranchName ?? '—',
                      doctorName: appointment.doctorDisplayName,
                      state: appointment.status.label,
                    ),
                ],
              ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = ref.watch(patientDetailHistoryTabProvider(widget.patientId));
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HistoryTabSelector(
              selectedTab: selectedTab,
              pastCount: widget.pastVisits.length,
              upcomingCount: widget.upcomingAppointments.length,
              onSelected: _onTabSelected,
            ),
            const SizedBox(height: SpacingTokens.lg),
            AnimatedSize(
              duration: _tabTransitionDuration,
              curve: AppPaginatedSlideSwitcher.curve,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: _tabTransitionDuration,
                  switchInCurve: AppPaginatedSlideSwitcher.curve,
                  switchOutCurve: AppPaginatedSlideSwitcher.curve,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        ...previousChildren.map((child) => Positioned(top: 0, left: 0, right: 0, child: child)),
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    final direction = _tabTransitionDirection.toDouble();
                    final slideAnimation = Tween<Offset>(
                      begin: Offset(direction, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: AppPaginatedSlideSwitcher.curve));

                    return SlideTransition(position: slideAnimation, child: child);
                  },
                  child: KeyedSubtree(
                    key: ValueKey<PatientDetailHistoryTab>(selectedTab),
                    child: _panelFor(selectedTab),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTabSelector extends StatelessWidget {
  const _HistoryTabSelector({
    required this.selectedTab,
    required this.pastCount,
    required this.upcomingCount,
    required this.onSelected,
  });

  final PatientDetailHistoryTab selectedTab;
  final int pastCount;
  final int upcomingCount;
  final ValueChanged<PatientDetailHistoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xs),
        child: Row(
          children: [
            Expanded(
              child: _HistoryTabButton(
                label: 'Past visits',
                count: pastCount,
                isSelected: selectedTab == PatientDetailHistoryTab.past,
                onTap: () => onSelected(PatientDetailHistoryTab.past),
              ),
            ),
            const SizedBox(width: SpacingTokens.xs),
            Expanded(
              child: _HistoryTabButton(
                label: 'Upcoming',
                count: upcomingCount,
                isSelected: selectedTab == PatientDetailHistoryTab.upcoming,
                onTap: () => onSelected(PatientDetailHistoryTab.upcoming),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTabButton extends StatelessWidget {
  const _HistoryTabButton({required this.label, required this.count, required this.isSelected, required this.onTap});

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: isSelected ? colors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(context.shapeTokens.sm),
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(context.shapeTokens.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm, horizontal: SpacingTokens.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? colors.foreground : colors.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SpacingTokens.xs),
                AppBadge(label: '$count', variant: isSelected ? AppBadgeVariant.outline : AppBadgeVariant.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelinePanelContent extends StatelessWidget {
  const _TimelinePanelContent({required this.child, this.isLoading = false, this.error, this.onRetry});

  final Widget child;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoading)
          const Center(
            child: Padding(padding: EdgeInsets.all(SpacingTokens.lg), child: AppCircularProgress()),
          )
        else if (error != null)
          _TimelineErrorState(message: error!, onRetry: onRetry)
        else
          child,
      ],
    );
  }
}

class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground)),
    );
  }
}

class _TimelineErrorState extends StatelessWidget {
  const _TimelineErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive)),
        if (onRetry != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          AppButton(label: 'Retry', expand: false, variant: AppButtonVariant.outline, onPressed: onRetry),
        ],
      ],
    );
  }
}

@immutable
class _VisitTimelineItem {
  const _VisitTimelineItem({
    required this.dateLabel,
    required this.timeLabel,
    required this.branch,
    required this.doctorName,
    required this.state,
  });

  final String dateLabel;
  final String timeLabel;
  final String branch;
  final String doctorName;
  final String state;
}

class _VisitsTimeline extends StatelessWidget {
  const _VisitsTimeline({required this.items});

  final List<_VisitTimelineItem> items;

  static const _timelineGutter = 40.0;
  static const _bubbleSize = 14.0;
  static const _lineWidth = 2.0;
  static const _cardGap = SpacingTokens.md;

  @override
  Widget build(BuildContext context) {
    final lineColor = context.semanticColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++)
          _VisitTimelineRow(
            item: items[index],
            bubbleFilled: index == 0,
            isFirst: index == 0,
            isLast: index == items.length - 1,
            lineColor: lineColor,
            gutterWidth: _timelineGutter,
            bubbleSize: _bubbleSize,
            lineWidth: _lineWidth,
            bottomGap: index < items.length - 1 ? _cardGap : 0,
          ),
      ],
    );
  }
}

class _VisitTimelineRow extends StatefulWidget {
  const _VisitTimelineRow({
    required this.item,
    required this.bubbleFilled,
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
    required this.gutterWidth,
    required this.bubbleSize,
    required this.lineWidth,
    required this.bottomGap,
  });

  final _VisitTimelineItem item;
  final bool bubbleFilled;
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
  final double gutterWidth;
  final double bubbleSize;
  final double lineWidth;
  final double bottomGap;

  static const _estimatedCardHeight = 72.0;

  @override
  State<_VisitTimelineRow> createState() => _VisitTimelineRowState();
}

class _VisitTimelineRowState extends State<_VisitTimelineRow> {
  final _cardKey = GlobalKey();
  var _cardHeight = _VisitTimelineRow._estimatedCardHeight;

  bool get _isSingle => widget.isFirst && widget.isLast;

  bool get _showLineAbove => _isSingle || !widget.isFirst;

  bool get _showLineBelow => _isSingle || !widget.isLast;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_syncCardHeight);
  }

  @override
  void didUpdateWidget(covariant _VisitTimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _cardHeight = _VisitTimelineRow._estimatedCardHeight;
    }
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
              painter: _TimelineGutterPainter(
                lineColor: widget.lineColor,
                lineWidth: widget.lineWidth,
                bubbleSize: widget.bubbleSize,
                bubbleFilled: widget.bubbleFilled,
                bubbleFillColor: colors.primary.withValues(alpha: 0.85),
                bubbleRingColor: colors.primary,
                bubbleCenterColor: colors.card,
                showLineAbove: _showLineAbove,
                showLineBelow: _showLineBelow,
                cardHeight: _cardHeight,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.bottomGap),
            child: KeyedSubtree(
              key: _cardKey,
              child: _VisitTimelineCard(item: widget.item),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineGutterPainter extends CustomPainter {
  const _TimelineGutterPainter({
    required this.lineColor,
    required this.lineWidth,
    required this.bubbleSize,
    required this.bubbleFilled,
    required this.bubbleFillColor,
    required this.bubbleRingColor,
    required this.bubbleCenterColor,
    required this.showLineAbove,
    required this.showLineBelow,
    required this.cardHeight,
  });

  final Color lineColor;
  final double lineWidth;
  final double bubbleSize;
  final bool bubbleFilled;
  final Color bubbleFillColor;
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
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    if (showLineAbove) {
      canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, center.dy - bubbleRadius), linePaint);
    }
    if (showLineBelow) {
      canvas.drawLine(Offset(center.dx, center.dy + bubbleRadius), Offset(center.dx, size.height), linePaint);
    }

    if (bubbleFilled) {
      canvas.drawCircle(center, bubbleRadius, Paint()..color = bubbleFillColor);
      return;
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
  bool shouldRepaint(covariant _TimelineGutterPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor ||
        lineWidth != oldDelegate.lineWidth ||
        bubbleSize != oldDelegate.bubbleSize ||
        bubbleFilled != oldDelegate.bubbleFilled ||
        bubbleFillColor != oldDelegate.bubbleFillColor ||
        bubbleRingColor != oldDelegate.bubbleRingColor ||
        bubbleCenterColor != oldDelegate.bubbleCenterColor ||
        showLineAbove != oldDelegate.showLineAbove ||
        showLineBelow != oldDelegate.showLineBelow ||
        cardHeight != oldDelegate.cardHeight;
  }
}

class _VisitTimelineCard extends StatelessWidget {
  const _VisitTimelineCard({required this.item});

  final _VisitTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        boxShadow: [
          BoxShadow(color: colors.foreground.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DateTimeSection(item: item, textTheme: textTheme, colors: colors),
                  const SizedBox(height: SpacingTokens.md),
                  _LabeledField(label: 'Branch', value: item.branch, textTheme: textTheme, colors: colors),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _LabeledField(
                          label: 'Doctor',
                          value: item.doctorName,
                          textTheme: textTheme,
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: SpacingTokens.md),
                      Expanded(
                        child: _LabeledField(label: 'State', value: item.state, textTheme: textTheme, colors: colors),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: _DateTimeSection(item: item, textTheme: textTheme, colors: colors),
                ),
                _TimelineSectionDivider(color: colors.border),
                Expanded(
                  flex: 2,
                  child: _LabeledField(label: 'Branch', value: item.branch, textTheme: textTheme, colors: colors),
                ),
                _TimelineSectionDivider(color: colors.border),
                Expanded(
                  flex: 2,
                  child: _LabeledField(label: 'Doctor', value: item.doctorName, textTheme: textTheme, colors: colors),
                ),
                _TimelineSectionDivider(color: colors.border),
                Expanded(
                  flex: 2,
                  child: _LabeledField(label: 'State', value: item.state, textTheme: textTheme, colors: colors),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DateTimeSection extends StatelessWidget {
  const _DateTimeSection({required this.item, required this.textTheme, required this.colors});

  final _VisitTimelineItem item;
  final TextTheme textTheme;
  final SemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          item.dateLabel,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.foreground),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(item.timeLabel, style: textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.value, required this.textTheme, required this.colors});

  final String label;
  final String value;
  final TextTheme textTheme;
  final SemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: textTheme.labelSmall?.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.foreground),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _TimelineSectionDivider extends StatelessWidget {
  const _TimelineSectionDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
      child: SizedBox(height: 40, child: VerticalDivider(width: 1, thickness: 1, color: color)),
    );
  }
}
