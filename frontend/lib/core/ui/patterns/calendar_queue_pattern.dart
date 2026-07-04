import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// View mode for [CalendarQueuePattern].
enum CalendarQueueView { calendar, queue }

/// One kanban-style column in the queue board.
class CalendarQueueColumn {
  const CalendarQueueColumn({required this.title, required this.cards, this.emptyLabel = 'Empty'});

  final String title;
  final List<Widget> cards;
  final String emptyLabel;
}

/// Calendar / queue page scaffold — toolbar, calendar, or queue board.
///
/// Composes [AppToolbar] (filters + [AppSegmentedControl] view switch) →
/// either an [AppCalendar] slot or queue columns of entity cards with status.
class CalendarQueuePattern extends StatelessWidget {
  const CalendarQueuePattern({
    required this.view,
    required this.onViewChanged,
    this.toolbarStart,
    this.toolbarEnd,
    this.calendar,
    this.calendarHeader,
    this.queueColumns = const [],
    this.queueHeader,
    this.viewSwitchSemanticLabel = 'Schedule view',
    super.key,
  });

  final Widget? toolbarStart;
  final Widget? toolbarEnd;
  final CalendarQueueView view;
  final ValueChanged<CalendarQueueView> onViewChanged;
  final Widget? calendar;
  final Widget? calendarHeader;
  final List<CalendarQueueColumn> queueColumns;
  final Widget? queueHeader;
  final String viewSwitchSemanticLabel;

  static const List<AppSegmentedOption<CalendarQueueView>> _viewOptions = [
    AppSegmentedOption(value: CalendarQueueView.calendar, label: 'Calendar', icon: LucideIcons.calendar),
    AppSegmentedOption(value: CalendarQueueView.queue, label: 'Queue', icon: LucideIcons.columns3),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);
        final showSideBySide = constraints.maxWidth >= AppBreakpoints.lg;

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppToolbar(
                start: toolbarStart,
                end: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppSegmentedControl<CalendarQueueView>(
                      options: _viewOptions,
                      value: view,
                      onChanged: onViewChanged,
                      semanticLabel: viewSwitchSemanticLabel,
                      size: AppSegmentedControlSize.sm,
                    ),
                    if (toolbarEnd != null) ...[const SizedBox(width: AppSpacing.s3), toolbarEnd!],
                  ],
                ),
                compactEnd: AppSegmentedControl<CalendarQueueView>(
                  options: _viewOptions,
                  value: view,
                  onChanged: onViewChanged,
                  semanticLabel: viewSwitchSemanticLabel,
                  size: AppSegmentedControlSize.sm,
                ),
              ),
              const SizedBox(height: PatternScaffold.sectionGap),
              Expanded(
                child: showSideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _CalendarSection(header: calendarHeader, calendar: calendar),
                          ),
                          const SizedBox(width: AppSpacing.s6),
                          Expanded(
                            child: _QueueBoardSection(header: queueHeader, columns: queueColumns),
                          ),
                        ],
                      )
                    : switch (view) {
                        CalendarQueueView.calendar => _CalendarSection(header: calendarHeader, calendar: calendar),
                        CalendarQueueView.queue => _QueueBoardSection(header: queueHeader, columns: queueColumns),
                      },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({this.header, this.calendar});

  final Widget? header;
  final Widget? calendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        if (header != null) const SizedBox(height: AppSpacing.s4),
        if (calendar != null) Expanded(child: calendar!),
      ],
    );
  }
}

class _QueueBoardSection extends StatelessWidget {
  const _QueueBoardSection({required this.columns, this.header});

  final Widget? header;
  final List<CalendarQueueColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        if (header != null) const SizedBox(height: AppSpacing.s4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useRowLayout = constraints.maxWidth >= AppBreakpoints.sm && columns.length > 1;

              if (useRowLayout) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.s3),
                      Expanded(child: _QueueColumnView(column: columns[i], constrained: true)),
                    ],
                  ],
                );
              }

              return AppScrollArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.s3),
                      _QueueColumnView(column: columns[i]),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QueueColumnView extends StatelessWidget {
  const _QueueColumnView({required this.column, this.constrained = false});

  final CalendarQueueColumn column;
  final bool constrained;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadii.lgAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.s1, bottom: AppSpacing.s2),
              child: Text(column.title, style: typography.overline.copyWith(color: colors.textTertiary)),
            ),
            if (constrained)
              Expanded(child: _QueueColumnCards(column: column, scrollable: true))
            else
              _QueueColumnCards(column: column),
          ],
        ),
      ),
    );
  }
}

class _QueueColumnCards extends StatelessWidget {
  const _QueueColumnCards({required this.column, this.scrollable = false});

  final CalendarQueueColumn column;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    if (column.cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1, vertical: AppSpacing.s4),
        child: Text(
          column.emptyLabel,
          textAlign: TextAlign.center,
          style: typography.caption.copyWith(color: colors.textTertiary),
        ),
      );
    }

    final cards = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < column.cards.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s2),
          column.cards[i],
        ],
      ],
    );

    if (scrollable) {
      return AppScrollArea(child: cards);
    }
    return cards;
  }
}
