import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// A single event in the timeline.
class TimelineEvent {
  const TimelineEvent({required this.time, required this.title, this.description, this.group});

  final String time;
  final String title;
  final String? description;
  final String? group;
}

/// A vertical timeline that displays a list of events with an optional
/// grouping header. Group headers render only when there are >1 distinct groups.
class AppTimeline extends StatelessWidget {
  const AppTimeline({super.key, required this.events});

  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final groups = <String, List<TimelineEvent>>{};
    for (final event in events) {
      final key = event.group ?? '';
      (groups[key] ??= []).add(event);
    }

    final showHeaders = groups.length > 1;
    final entries = showHeaders ? groups.entries.toList() : [MapEntry('', events)];

    return Semantics(
      label: 'Timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.space8),
            _TimelineGroup(group: entries[i].key, events: entries[i].value, showHeader: showHeaders, colors: colors),
          ],
        ],
      ),
    );
  }
}

class _TimelineGroup extends StatelessWidget {
  const _TimelineGroup({required this.group, required this.events, required this.showHeader, required this.colors});

  final String group;
  final List<TimelineEvent> events;
  final bool showHeader;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader && group.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space4),
            child: Text(group, style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < events.length; i++)
              _TimelineItem(event: events[i], isLast: i == events.length - 1, colors: colors),
          ],
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.isLast, required this.colors});

  final TimelineEvent event;
  final bool isLast;
  final AppSemanticColors colors;

  static const double _dotSize = 10.0;
  static const double _borderWidth = 2.0;
  static const double _dotOverhang = (_dotSize - _borderWidth) / 2;
  static const double _dotTop = 6.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.space8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: AppSpacing.space6 + _dotOverhang,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: _dotOverhang,
                    top: 0,
                    bottom: 0,
                    width: _borderWidth,
                    child: ColoredBox(color: colors.borderSubtle),
                  ),
                  PositionedDirectional(
                    start: 0,
                    top: _dotTop,
                    child: _TimelineDot(colors: colors),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.time,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  Text(event.title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                  if (event.description != null) ...[
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      event.description!,
                      style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.actionPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surfaceDefault, width: _TimelineItem._borderWidth),
      ),
      child: const SizedBox.square(dimension: _TimelineItem._dotSize),
    );
  }
}
