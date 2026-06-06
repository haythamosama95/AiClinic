import 'dart:async';

import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/shifts/domain/shift_calendar_mode.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_event_tile.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_month_day_sheet.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Branch shift calendar with weekly and monthly views (V1-7 US2).
class ShiftCalendarPage extends ConsumerStatefulWidget {
  const ShiftCalendarPage({super.key});

  @override
  ConsumerState<ShiftCalendarPage> createState() => _ShiftCalendarPageState();
}

class _ShiftCalendarPageState extends ConsumerState<ShiftCalendarPage> {
  static const double _calendarViewportHeight = 640;

  final EventController<ShiftListItem> _eventController = EventController<ShiftListItem>();
  final GlobalKey<WeekViewState<ShiftListItem>> _weekViewKey = GlobalKey<WeekViewState<ShiftListItem>>();
  final GlobalKey<MonthViewState<ShiftListItem>> _monthViewKey = GlobalKey<MonthViewState<ShiftListItem>>();
  int _eventsFingerprint = 0;
  ShiftCalendarMode? _renderedMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(shiftCalendarProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canView = ref.watch(permissionServiceProvider).canViewShifts();
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();
    final state = ref.watch(shiftCalendarProvider);
    final controller = ref.read(shiftCalendarProvider.notifier);

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift Calendar')),
        body: const Center(
          key: Key('shift_calendar_permission_denied'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You must be assigned to a branch to view the shift calendar.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final modeChanged = _renderedMode != null && _renderedMode != state.mode;
    _renderedMode = state.mode;
    if (modeChanged) {
      _eventsFingerprint = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncCalendarEvents(ref.read(shiftCalendarProvider).items);
      });
    } else {
      _syncCalendarEvents(state.items);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Shift Calendar')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('shift_calendar_create_fab'),
              onPressed: () async {
                await context.push(AppRoutes.shiftsNew);
                if (!mounted) {
                  return;
                }
                await controller.refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create shift'),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(state, controller),
            const SizedBox(height: 12),
            Text(_rangeLabel(context, state), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (!state.loading && state.error != null) ...[
              Text(
                state.error!,
                key: const Key('shift_calendar_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('shift_calendar_retry'),
                onPressed: controller.refresh,
                child: const Text('Retry'),
              ),
            ],
            if (!state.loading && state.error == null && state.items.isEmpty) ...[
              _EmptyState(canManage: canManage),
              const SizedBox(height: 16),
            ],
            if (state.error == null)
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: state.mode == ShiftCalendarMode.week
                            ? WeekView<ShiftListItem>(
                                key: _weekViewKey,
                                controller: _eventController,
                                initialDay: state.focusDate,
                                onPageChange: (date, _) => controller.setFocusDate(date),
                                onEventTap: _onWeekEventTap,
                                eventTileBuilder: ShiftEventTile.weekBuilder,
                                startHour: 6,
                                endHour: 22,
                                heightPerMinute: _calendarViewportHeight / ((22 - 6) * 60),
                              )
                            : MonthView<ShiftListItem>(
                                key: _monthViewKey,
                                controller: _eventController,
                                monthViewStyle: MonthViewStyle(
                                  initialMonth: DateTime(state.focusDate.year, state.focusDate.month),
                                  useAvailableVerticalSpace: true,
                                ),
                                monthViewBuilders: MonthViewBuilders(
                                  onPageChange: (date, _) => controller.setFocusDate(date),
                                  onCellTap: _onMonthCellTap,
                                  cellBuilder: _buildMonthCellFromObjectEvents,
                                ),
                              ),
                      ),
                    ),
                    if (state.loading)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                          child: const Center(key: Key('shift_calendar_loading'), child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _syncCalendarEvents(List<ShiftListItem> items) {
    final fingerprint = Object.hashAll(
      items.map((item) => Object.hash(item.id, item.shiftDate, item.startTime, item.endTime, item.status)),
    );
    if (fingerprint == _eventsFingerprint) {
      return;
    }

    _eventsFingerprint = fingerprint;
    _eventController
      ..clear()
      ..addAll(
        items
            .map((item) {
              final start = _dateTimeForShift(item);
              final end = _endDateTimeForShift(item);
              return CalendarEventData<ShiftListItem>(
                date: start,
                startTime: start,
                endTime: end,
                title: item.assigneeSummary,
                description: '${item.startTime}–${item.endTime}',
                color: _statusColor(item.status),
                event: item,
              );
            })
            .toList(growable: false),
      );
  }

  DateTime _dateTimeForShift(ShiftListItem item) {
    final (hour, minute) = _parseHm(item.startTime);
    return DateTime(item.shiftDate.year, item.shiftDate.month, item.shiftDate.day, hour, minute);
  }

  DateTime _endDateTimeForShift(ShiftListItem item) {
    final (hour, minute) = _parseHm(item.endTime);
    return DateTime(item.shiftDate.year, item.shiftDate.month, item.shiftDate.day, hour, minute);
  }

  (int, int) _parseHm(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      return (9, 0);
    }
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  Color _statusColor(ShiftStatus status) {
    return switch (status) {
      ShiftStatus.active => Colors.teal,
      ShiftStatus.incomplete => Colors.orange,
      ShiftStatus.cancelled => Colors.red,
      ShiftStatus.unknown => Colors.grey,
    };
  }

  void _onWeekEventTap(List<CalendarEventData<ShiftListItem>> events, DateTime date) {
    final item = events.firstOrNull?.event;
    if (item == null) {
      return;
    }
    context.push(AppRoutes.shiftDetail(item.id));
  }

  Widget _buildMonthCellFromObjectEvents(
    DateTime date,
    List<CalendarEventData<Object?>> events,
    bool isToday,
    bool isInMonth,
    bool hideDaysNotInMonth,
  ) {
    return _buildMonthCell(
      date,
      events.cast<CalendarEventData<ShiftListItem>>(),
      isToday,
      isInMonth,
      hideDaysNotInMonth,
    );
  }

  void _onMonthCellTap(List<CalendarEventData<Object?>> events, DateTime date) {
    if (events.isEmpty) {
      return;
    }

    final day = DateTime(date.year, date.month, date.day);
    final shifts = events.map((event) => event.event).whereType<ShiftListItem>().toList(growable: false)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    ShiftMonthDaySheet.show(context, date: day, shifts: shifts);
  }

  Widget _buildMonthCell(
    DateTime date,
    List<CalendarEventData<ShiftListItem>> events,
    bool isToday,
    bool isInMonth,
    bool hideDaysNotInMonth,
  ) {
    final dayShifts = events.map((event) => event.event).whereType<ShiftListItem>().toList(growable: false);
    final unassignedCount = dayShifts.where((shift) => shift.isUnassigned).length;
    final textColor = isInMonth ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.outline;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
        color: isToday ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
            ),
            if (dayShifts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '${dayShifts.length} shift${dayShifts.length == 1 ? '' : 's'}',
                key: Key('shift_month_cell_count_${date.year}_${date.month}_${date.day}'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (unassignedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ShiftStatusBadge(status: ShiftStatus.incomplete, isUnassigned: true),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ShiftCalendarState state, ShiftCalendarController controller) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<ShiftCalendarMode>(
          key: const Key('shift_calendar_mode_toggle'),
          segments: const [
            ButtonSegment(value: ShiftCalendarMode.week, label: Text('Week'), icon: Icon(Icons.view_week)),
            ButtonSegment(value: ShiftCalendarMode.month, label: Text('Month'), icon: Icon(Icons.calendar_month)),
          ],
          selected: {state.mode},
          onSelectionChanged: (selection) => controller.setMode(selection.first),
        ),
        IconButton(
          key: const Key('shift_calendar_previous'),
          tooltip: 'Previous',
          onPressed: () async {
            await controller.previousPeriod();
            _animateToFocus(state.mode);
          },
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const Key('shift_calendar_next'),
          tooltip: 'Next',
          onPressed: () async {
            await controller.nextPeriod();
            _animateToFocus(state.mode);
          },
          icon: const Icon(Icons.chevron_right),
        ),
        OutlinedButton(
          key: const Key('shift_calendar_today'),
          onPressed: () {
            final today = DateTime.now();
            controller.setFocusDate(today);
            _animateToFocus(state.mode, date: today);
          },
          child: const Text('Today'),
        ),
      ],
    );
  }

  void _animateToFocus(ShiftCalendarMode mode, {DateTime? date}) {
    final focus = date ?? ref.read(shiftCalendarProvider).focusDate;
    if (mode == ShiftCalendarMode.week) {
      _weekViewKey.currentState?.animateToWeek(focus);
    } else {
      _monthViewKey.currentState?.animateToMonth(focus);
    }
  }

  String _rangeLabel(BuildContext context, ShiftCalendarState state) {
    final localizations = MaterialLocalizations.of(context);
    final (start, end) = ShiftCalendarController.boundsFor(state.focusDate, state.mode);

    if (state.mode == ShiftCalendarMode.month) {
      return localizations.formatMonthYear(DateTime(state.focusDate.year, state.focusDate.month));
    }

    return '${localizations.formatMediumDate(start)} – ${localizations.formatMediumDate(end)}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('shift_calendar_empty'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          canManage
              ? 'No shifts are scheduled for this period. Create the first shift to start planning coverage.'
              : 'No shifts are scheduled for this period.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
