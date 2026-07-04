import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// A single chronological entry for [AppTimeline].
@immutable
class AppTimelineEvent {
  const AppTimelineEvent({
    required this.id,
    required this.timestamp,
    required this.title,
    this.description,
    this.group,
  });

  final String id;
  final String timestamp;
  final String title;
  final Widget? description;

  /// Optional day header (e.g. "Today", "Jul 4, 2026").
  final String? group;
}

/// Chronological event list with connector, nodes, and optional day grouping.
class AppTimeline extends StatelessWidget {
  const AppTimeline({
    required this.events,
    super.key,
  });

  final List<AppTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final groups = _groupEvents(events);
    final showHeaders = groups.length > 1;

    return Semantics(
      container: true,
      label: 'Timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in groups.entries) ...[
            if (showHeaders && entry.key.isNotEmpty) ...[
              _GroupHeader(label: entry.key),
              const SizedBox(height: AppSpacing.s4),
            ],
            _TimelineGroup(events: entry.value),
            if (entry != groups.entries.last) const SizedBox(height: AppSpacing.s8),
          ],
        ],
      ),
    );
  }

  Map<String, List<AppTimelineEvent>> _groupEvents(
    List<AppTimelineEvent> events,
  ) {
    final groups = <String, List<AppTimelineEvent>>{};
    for (final event in events) {
      final key = event.group ?? '';
      groups.putIfAbsent(key, () => []).add(event);
    }
    return groups;
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Text(
      label,
      style: typography.overline.copyWith(color: colors.textTertiary),
    );
  }
}

class _TimelineGroup extends StatelessWidget {
  const _TimelineGroup({required this.events});

  final List<AppTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        PositionedDirectional(
          start: AppSpacing.s1 + AppSpacing.sPx,
          top: AppSpacing.s1 + AppSpacing.s0_5,
          bottom: 0,
          child: Container(
            width: AppSpacing.s0_5,
            color: colors.borderSubtle,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < events.length; i++)
              _TimelineEntry(
                event: events[i],
                isLast: i == events.length - 1,
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.event,
    required this.isLast,
  });

  final AppTimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final nodeSize = AppSpacing.s2 + AppSpacing.s0_5;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.s6,
        bottom: isLast ? 0 : AppSpacing.s8,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            start: -(AppSpacing.s6 - AppSpacing.s1 - AppSpacing.sPx),
            top: AppSpacing.s1 + AppSpacing.s0_5,
            child: Container(
              width: nodeSize,
              height: nodeSize,
              decoration: BoxDecoration(
                color: colors.actionPrimary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.surfaceDefault,
                  width: AppSpacing.s0_5,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.timestamp,
                style: typography.tabular(typography.caption).copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                event.title,
                style: typography.bodyStrong.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (event.description != null) ...[
                const SizedBox(height: AppSpacing.s1),
                DefaultTextStyle(
                  style: typography.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                  child: event.description!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
