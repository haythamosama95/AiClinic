import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';

/// Visible calendar layout modes.
enum AppCalendarView { day, week, month, agenda }

/// Optional semantic status for [AppCalendarEvent] chips and badges.
enum AppCalendarEventStatus { neutral, success, warning, danger, info }

/// Doctor, room, or other schedulable resource shown in filters and columns.
@immutable
class AppCalendarResource {
  const AppCalendarResource({required this.id, required this.displayName, this.branchId, this.color});

  final String id;
  final String displayName;
  final String? branchId;
  final Color? color;
}

/// Domain event rendered by [AppCalendar].
///
/// Syncfusion types are adapted internally; consumers only use this model.
@immutable
class AppCalendarEvent {
  const AppCalendarEvent({
    required this.id,
    required this.start,
    required this.end,
    required this.title,
    this.resourceId,
    this.branchId,
    this.color,
    this.status = AppCalendarEventStatus.neutral,
    this.allDay = false,
    this.hasConflict,
    this.subtitle,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final String title;
  final String? resourceId;
  final String? branchId;
  final Color? color;
  final AppCalendarEventStatus status;
  final bool allDay;

  /// When `null`, overlap with another event is computed automatically.
  final bool? hasConflict;
  final String? subtitle;
}

/// Draft passed to [AppCalendar.onCreate] for tap/long-press creation gestures.
@immutable
class AppCalendarCreateDetails {
  const AppCalendarCreateDetails({required this.start, required this.end, this.allDay = false, this.resourceId});

  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? resourceId;
}

/// Token-styled scheduling surface wrapping Syncfusion behind an App-owned API.
class AppCalendar extends StatefulWidget {
  const AppCalendar({
    this.events = const [],
    this.view,
    this.onViewChanged,
    this.selectedDate,
    this.onDateChanged,
    this.onEventTap,
    this.onCreate,
    this.resources,
    this.selectedResourceIds,
    this.onResourceFilterChanged,
    this.selectedBranchIds,
    this.onBranchFilterChanged,
    this.density,
    this.startHour = 8,
    this.endHour = 20,
    super.key,
  });

  final List<AppCalendarEvent> events;
  final AppCalendarView? view;
  final ValueChanged<AppCalendarView>? onViewChanged;
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateChanged;
  final ValueChanged<AppCalendarEvent>? onEventTap;
  final ValueChanged<AppCalendarCreateDetails>? onCreate;
  final List<AppCalendarResource>? resources;
  final Set<String>? selectedResourceIds;
  final ValueChanged<Set<String>>? onResourceFilterChanged;
  final Set<String>? selectedBranchIds;
  final ValueChanged<Set<String>>? onBranchFilterChanged;
  final AppDensity? density;
  final int startHour;
  final int endHour;

  @override
  State<AppCalendar> createState() => _AppCalendarState();
}

class _AppCalendarState extends State<AppCalendar> {
  static const _westernTimeLocale = 'en-GB';
  static const _defaultDuration = Duration(minutes: 30);
  static const _timeRulerWidth = AppSpacing.s12 + AppSpacing.s2;
  static const _viewHeaderHeight = AppSpacing.s10;

  late AppCalendarView _view;
  late DateTime _selectedDate;
  late final CalendarController _controller;
  _AppCalendarDataSource? _dataSource;

  @override
  void initState() {
    super.initState();
    _view = widget.view ?? AppCalendarView.week;
    _selectedDate = widget.selectedDate ?? DateTime.now();
    _controller = CalendarController()
      ..displayDate = _selectedDate
      ..selectedDate = _selectedDate
      ..view = _toSyncfusionView(_view);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataSource ??= _createDataSource();
  }

  @override
  void didUpdateWidget(covariant AppCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.view != null && widget.view != oldWidget.view) {
      _view = widget.view!;
      _controller.view = _toSyncfusionView(_view);
    }
    if (widget.selectedDate != null && widget.selectedDate != oldWidget.selectedDate) {
      _selectedDate = widget.selectedDate!;
      _controller.displayDate = _selectedDate;
      _controller.selectedDate = _selectedDate;
    }
    if (widget.events != oldWidget.events ||
        widget.resources != oldWidget.resources ||
        widget.selectedResourceIds != oldWidget.selectedResourceIds ||
        widget.selectedBranchIds != oldWidget.selectedBranchIds) {
      _rebuildDataSource();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CalendarView _toSyncfusionView(AppCalendarView view) {
    return switch (view) {
      AppCalendarView.day => CalendarView.day,
      AppCalendarView.week => CalendarView.week,
      AppCalendarView.month => CalendarView.month,
      AppCalendarView.agenda => CalendarView.schedule,
    };
  }

  List<AppCalendarEvent> get _filteredEvents {
    var events = widget.events;
    final resourceFilter = widget.selectedResourceIds;
    if (resourceFilter != null && resourceFilter.isNotEmpty) {
      events = events
          .where((event) => event.resourceId != null && resourceFilter.contains(event.resourceId))
          .toList(growable: false);
    }
    final branchFilter = widget.selectedBranchIds;
    if (branchFilter != null && branchFilter.isNotEmpty) {
      events = events
          .where((event) => event.branchId != null && branchFilter.contains(event.branchId))
          .toList(growable: false);
    }
    return events;
  }

  Set<String> get _conflictIds => _computeConflictIds(_filteredEvents);

  _AppCalendarDataSource _createDataSource() {
    return _AppCalendarDataSource(
      events: _filteredEvents,
      conflictIds: _conflictIds,
      resources: widget.resources,
      fallbackColor: context.colors.actionPrimary,
    );
  }

  void _rebuildDataSource() {
    final existing = _dataSource;
    if (existing == null) {
      _dataSource = _createDataSource();
      return;
    }
    existing.update(
      events: _filteredEvents,
      conflictIds: _conflictIds,
      resources: widget.resources,
      fallbackColor: context.colors.actionPrimary,
    );
  }

  double get _timeIntervalHeight {
    final density = widget.density ?? AppDensity.standard;
    return switch (density) {
      AppDensity.compact => AppSpacing.s8 + AppSpacing.s2,
      AppDensity.standard => AppSpacing.s10,
      AppDensity.comfortable => AppSpacing.s12,
    };
  }

  int get _firstDayOfWeek {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return isRtl ? DateTime.saturday : DateTime.sunday;
  }

  void _setView(AppCalendarView view) {
    _controller.view = _toSyncfusionView(view);
    if (widget.view == null) {
      setState(() => _view = view);
    }
    _deferAfterCalendarFrame(() {
      widget.onViewChanged?.call(view);
    });
  }

  void _setDate(DateTime date, {bool updateController = true}) {
    final normalized = DateTime(date.year, date.month, date.day);
    final current = widget.selectedDate ?? _selectedDate;
    if (_isSameDay(current, normalized)) {
      return;
    }
    widget.onDateChanged?.call(normalized);
    if (widget.selectedDate == null) {
      setState(() => _selectedDate = normalized);
    } else {
      _selectedDate = normalized;
    }
    if (updateController) {
      _controller.displayDate = normalized;
      _controller.selectedDate = normalized;
    }
  }

  void _deferAfterCalendarFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  void _navigate(int delta) {
    final current = widget.selectedDate ?? _selectedDate;
    final next = switch (_view) {
      AppCalendarView.month => DateTime(current.year, current.month + delta),
      AppCalendarView.week => current.add(Duration(days: delta * 7)),
      AppCalendarView.agenda => current.add(Duration(days: delta * 7)),
      AppCalendarView.day => current.add(Duration(days: delta)),
    };
    _setDate(next);
  }

  void _goToToday() => _setDate(DateTime.now());

  bool get _showsTimeGrid => _view == AppCalendarView.day || _view == AppCalendarView.week;

  bool get _showsNowIndicator {
    if (!_showsTimeGrid) return false;
    final now = DateTime.now();
    final anchor = widget.selectedDate ?? _selectedDate;
    return switch (_view) {
      AppCalendarView.day => _isSameDay(now, anchor),
      AppCalendarView.week => _isSameWeek(now, anchor, _firstDayOfWeek),
      _ => false,
    };
  }

  void _handleTap(CalendarTapDetails details) {
    if (details.targetElement == CalendarElement.appointment) return;

    if (widget.onCreate == null || details.date == null) return;

    final allowsCreate =
        details.targetElement == CalendarElement.calendarCell || details.targetElement == CalendarElement.allDayPanel;
    if (!allowsCreate) return;

    final start = details.date!.toLocal();
    final allDay = details.targetElement == CalendarElement.allDayPanel;
    final end = allDay ? start.add(const Duration(days: 1)) : start.add(_defaultDuration);
    widget.onCreate!(
      AppCalendarCreateDetails(start: start, end: end, allDay: allDay, resourceId: details.resource?.id as String?),
    );
  }

  void _handleLongPress(CalendarLongPressDetails details) {
    if (widget.onCreate == null || details.date == null) return;
    if (details.targetElement != CalendarElement.calendarCell && details.targetElement != CalendarElement.allDayPanel) {
      return;
    }
    if (details.appointments != null && details.appointments!.isNotEmpty) {
      return;
    }

    final start = details.date!.toLocal();
    final allDay = details.targetElement == CalendarElement.allDayPanel;
    final end = allDay ? start.add(const Duration(days: 1)) : start.add(_defaultDuration);
    widget.onCreate!(
      AppCalendarCreateDetails(start: start, end: end, allDay: allDay, resourceId: details.resource?.id as String?),
    );
  }

  void _handleViewChanged(ViewChangedDetails details) {
    final visible = details.visibleDates;
    if (visible.isEmpty) return;
    final midpoint = visible[visible.length ~/ 2];
    final normalized = DateTime(midpoint.year, midpoint.month, midpoint.day);

    // SfCalendar fires this before its build cycle completes. Defer parent
    // notifications and avoid controller writes so the element tree stays stable.
    _deferAfterCalendarFrame(() {
      _setDate(normalized, updateController: false);
    });
  }

  SfCalendarThemeData _calendarTheme(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final tabularTime = typography.tabular(typography.caption.copyWith(color: colors.textTertiary));

    return SfCalendarThemeData(
      backgroundColor: colors.surfaceDefault,
      headerBackgroundColor: colors.surfaceDefault,
      viewHeaderBackgroundColor: colors.surfaceDefault,
      agendaBackgroundColor: colors.surfaceDefault,
      allDayPanelColor: colors.surfaceSunken,
      cellBorderColor: colors.borderSubtle,
      todayHighlightColor: colors.borderFocus,
      todayBackgroundColor: colors.surfaceSelected,
      selectionBorderColor: colors.borderFocus,
      activeDatesBackgroundColor: colors.surfaceDefault,
      trailingDatesBackgroundColor: colors.surfaceSunken,
      leadingDatesBackgroundColor: colors.surfaceSunken,
      headerTextStyle: typography.bodyStrong.copyWith(color: colors.textPrimary),
      viewHeaderDayTextStyle: typography.caption.copyWith(color: colors.textTertiary),
      viewHeaderDateTextStyle: typography.tabular(typography.bodyStrong.copyWith(color: colors.textPrimary)),
      timeTextStyle: tabularTime,
      agendaDayTextStyle: typography.overline.copyWith(color: colors.textTertiary),
      agendaDateTextStyle: typography.tabular(typography.bodyStrong.copyWith(color: colors.textPrimary)),
      activeDatesTextStyle: typography.bodySm.copyWith(color: colors.textPrimary),
      trailingDatesTextStyle: typography.caption.copyWith(color: colors.textDisabled),
      leadingDatesTextStyle: typography.caption.copyWith(color: colors.textDisabled),
      todayTextStyle: typography.tabular(typography.bodyStrong.copyWith(color: colors.textPrimary)),
      timeIndicatorTextStyle: tabularTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final view = widget.view ?? _view;
    final anchorDate = widget.selectedDate ?? _selectedDate;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final showAgendaEmpty = view == AppCalendarView.agenda && _filteredEvents.isEmpty;
    final dataSource = _dataSource!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: Shortcuts(
          shortcuts: _keyboardShortcuts(isRtl),
          child: Actions(
            actions: _keyboardActions(),
            child: Focus(
              autofocus: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppCalendarHeader(
                    title: _headerTitle(context, view, anchorDate),
                    view: view,
                    isRtl: isRtl,
                    onPrevious: () => _navigate(-1),
                    onNext: () => _navigate(1),
                    onToday: _goToToday,
                    onViewChanged: _setView,
                  ),
                  if (widget.resources != null && widget.resources!.isNotEmpty)
                    _ResourceFilterBar(
                      resources: widget.resources!,
                      selectedResourceIds: widget.selectedResourceIds ?? const {},
                      onResourceFilterChanged: widget.onResourceFilterChanged,
                      selectedBranchIds: widget.selectedBranchIds ?? const {},
                      onBranchFilterChanged: widget.onBranchFilterChanged,
                    ),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SfCalendarTheme(
                          data: _calendarTheme(context),
                          child: SfCalendar(
                            key: ValueKey(view),
                            controller: _controller,
                            view: _toSyncfusionView(view),
                            dataSource: dataSource,
                            headerHeight: 0,
                            showNavigationArrow: false,
                            showTodayButton: false,
                            showCurrentTimeIndicator: false,
                            firstDayOfWeek: _firstDayOfWeek,
                            backgroundColor: colors.surfaceDefault,
                            todayHighlightColor: colors.surfaceSelected,
                            cellBorderColor: colors.borderSubtle,
                            selectionDecoration: BoxDecoration(
                              color: colors.surfaceSelected,
                              border: Border.all(color: colors.borderFocus),
                              borderRadius: AppRadii.mdAll,
                            ),
                            allowDragAndDrop: false,
                            allowAppointmentResize: false,
                            appointmentBuilder: _buildAppointment,
                            onTap: _handleTap,
                            onLongPress: _handleLongPress,
                            onViewChanged: _handleViewChanged,
                            timeSlotViewSettings: TimeSlotViewSettings(
                              startHour: widget.startHour.toDouble(),
                              endHour: widget.endHour.toDouble(),
                              timeInterval: const Duration(hours: 1),
                              timeIntervalHeight: _timeIntervalHeight,
                              timeFormat: 'h a',
                              timeRulerSize: _timeRulerWidth,
                              timeTextStyle: context.typography.tabular(
                                context.typography.caption.copyWith(color: colors.textTertiary),
                              ),
                            ),
                            monthViewSettings: MonthViewSettings(
                              appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                              monthCellStyle: MonthCellStyle(
                                todayBackgroundColor: colors.surfaceSelected,
                                trailingDatesBackgroundColor: colors.surfaceSunken,
                                leadingDatesBackgroundColor: colors.surfaceSunken,
                                textStyle: context.typography.caption.copyWith(color: colors.textSecondary),
                              ),
                            ),
                            scheduleViewSettings: ScheduleViewSettings(
                              appointmentItemHeight: AppSpacing.s8 + AppSpacing.s4,
                              hideEmptyScheduleWeek: false,
                              monthHeaderSettings: MonthHeaderSettings(
                                monthFormat: 'MMMM yyyy',
                                height: AppSpacing.s10,
                                textAlign: TextAlign.center,
                                backgroundColor: colors.surfaceDefault,
                                monthTextStyle: context.typography.bodyStrong.copyWith(color: colors.textPrimary),
                              ),
                            ),
                          ),
                        ),
                        if (showAgendaEmpty)
                          Positioned.fill(
                            child: ColoredBox(
                              color: colors.surfaceDefault,
                              child: const AppEmptyState(
                                variant: AppEmptyStateVariant.noResults,
                                title: 'No events',
                                description: 'Nothing scheduled for this period.',
                              ),
                            ),
                          )
                        else if (_showsNowIndicator)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _NowSignalOverlay(
                                view: view,
                                anchorDate: anchorDate,
                                startHour: widget.startHour,
                                endHour: widget.endHour,
                                timeIntervalHeight: _timeIntervalHeight,
                                timeRulerWidth: _timeRulerWidth,
                                viewHeaderHeight: _viewHeaderHeight,
                                isRtl: isRtl,
                                firstDayOfWeek: _firstDayOfWeek,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointment(BuildContext context, CalendarAppointmentDetails details) {
    final colors = context.colors;
    final typography = context.typography;
    final bounds = details.bounds;
    final appointment = details.appointments.first;
    final event = _dataSource?.eventFor(appointment);
    if (event == null) return const SizedBox.shrink();

    final conflict = event.hasConflict ?? _conflictIds.contains(event.id);
    final bg = conflict ? colors.statusDangerSurface : (event.color ?? colors.surfaceSelected);
    final border = conflict ? Border.all(color: colors.statusDangerBorder) : null;
    final fg = conflict ? colors.statusDangerFg : colors.textPrimary;

    final tile = Container(
      width: bounds.width,
      height: bounds.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: AppSpacing.s1),
      decoration: BoxDecoration(color: bg, border: border, borderRadius: AppRadii.mdAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
          if (event.subtitle != null && bounds.height > AppSpacing.s8)
            Text(
              event.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.caption.copyWith(color: conflict ? fg : colors.textSecondary),
            ),
          if (conflict && bounds.height > AppSpacing.s10)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.s1),
              child: AppBadge(
                variant: AppBadgeVariant.soft,
                color: AppBadgeColor.danger,
                size: AppBadgeSize.sm,
                label: 'Overlap',
              ),
            ),
        ],
      ),
    );

    final layerLink = LayerLink();
    return Semantics(
      button: true,
      label: event.title,
      child: CompositedTransformTarget(
        link: layerLink,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onEventTap?.call(event);
            showAppPopover(
              context: context,
              anchorLink: layerLink,
              placement: AppPopoverPlacement.bottomStart,
              builder: (popoverContext, dismiss) =>
                  _EventDetailPopover(event: event, conflict: conflict, onDismiss: dismiss),
            );
          },
          child: tile,
        ),
      ),
    );
  }

  String _headerTitle(BuildContext context, AppCalendarView view, DateTime anchorDate) {
    final locale = appInputIntlLocale(context);
    return switch (view) {
      AppCalendarView.month => DateFormat.yMMMM(locale).format(anchorDate),
      AppCalendarView.week => _weekRangeLabel(context, anchorDate),
      AppCalendarView.agenda => _weekRangeLabel(context, anchorDate),
      AppCalendarView.day => DateFormat.yMMMMEEEEd(locale).format(anchorDate),
    };
  }

  String _weekRangeLabel(BuildContext context, DateTime anchorDate) {
    final locale = appInputIntlLocale(context);
    final start = _weekStart(anchorDate, _firstDayOfWeek);
    final end = start.add(const Duration(days: 6));
    final startLabel = DateFormat('d MMM', locale).format(start);
    final endLabel = DateFormat('d MMM yyyy', locale).format(end);
    return '$startLabel – $endLabel';
  }
}

class _AppCalendarHeader extends StatelessWidget {
  const _AppCalendarHeader({
    required this.title,
    required this.view,
    required this.isRtl,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onViewChanged,
  });

  final String title;
  final AppCalendarView view;
  final bool isRtl;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<AppCalendarView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final prevIcon = isRtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft;
    final nextIcon = isRtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s4, AppSpacing.s3, AppSpacing.s4, AppSpacing.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s3,
        runSpacing: AppSpacing.s2,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: prevIcon,
                semanticLabel: 'Previous',
                size: AppIconButtonSize.sm,
                onPressed: onPrevious,
              ),
              AppIconButton(icon: nextIcon, semanticLabel: 'Next', size: AppIconButtonSize.sm, onPressed: onNext),
              const SizedBox(width: AppSpacing.s2),
              Text(title, style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSegmentedControl<AppCalendarView>(
                semanticLabel: 'Calendar view',
                size: AppSegmentedControlSize.sm,
                value: view,
                onChanged: onViewChanged,
                options: const [
                  AppSegmentedOption(value: AppCalendarView.day, label: 'Day'),
                  AppSegmentedOption(value: AppCalendarView.week, label: 'Week'),
                  AppSegmentedOption(value: AppCalendarView.month, label: 'Month'),
                  AppSegmentedOption(value: AppCalendarView.agenda, label: 'Agenda'),
                ],
              ),
              const SizedBox(width: AppSpacing.s2),
              AppButton(
                label: 'Today',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: onToday,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceFilterBar extends StatelessWidget {
  const _ResourceFilterBar({
    required this.resources,
    required this.selectedResourceIds,
    required this.onResourceFilterChanged,
    required this.selectedBranchIds,
    required this.onBranchFilterChanged,
  });

  final List<AppCalendarResource> resources;
  final Set<String> selectedResourceIds;
  final ValueChanged<Set<String>>? onResourceFilterChanged;
  final Set<String> selectedBranchIds;
  final ValueChanged<Set<String>>? onBranchFilterChanged;

  @override
  Widget build(BuildContext context) {
    final branchIds = {
      for (final resource in resources)
        if (resource.branchId != null) resource.branchId!,
    };

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s4, AppSpacing.s2, AppSpacing.s4, AppSpacing.s2),
      child: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          if (onResourceFilterChanged != null)
            for (final resource in resources)
              AppChip(
                selectable: true,
                selected: selectedResourceIds.contains(resource.id),
                onSelect: () {
                  final next = Set<String>.from(selectedResourceIds);
                  if (next.contains(resource.id)) {
                    next.remove(resource.id);
                  } else {
                    next.add(resource.id);
                  }
                  onResourceFilterChanged!(next);
                },
                child: Text(resource.displayName),
              ),
          if (onBranchFilterChanged != null)
            for (final branchId in branchIds)
              AppChip(
                selectable: true,
                selected: selectedBranchIds.contains(branchId),
                onSelect: () {
                  final next = Set<String>.from(selectedBranchIds);
                  if (next.contains(branchId)) {
                    next.remove(branchId);
                  } else {
                    next.add(branchId);
                  }
                  onBranchFilterChanged!(next);
                },
                child: Text(branchId),
              ),
        ],
      ),
    );
  }
}

class _NowSignalOverlay extends StatefulWidget {
  const _NowSignalOverlay({
    required this.view,
    required this.anchorDate,
    required this.startHour,
    required this.endHour,
    required this.timeIntervalHeight,
    required this.timeRulerWidth,
    required this.viewHeaderHeight,
    required this.isRtl,
    required this.firstDayOfWeek,
  });

  final AppCalendarView view;
  final DateTime anchorDate;
  final int startHour;
  final int endHour;
  final double timeIntervalHeight;
  final double timeRulerWidth;
  final double viewHeaderHeight;
  final bool isRtl;
  final int firstDayOfWeek;

  @override
  State<_NowSignalOverlay> createState() => _NowSignalOverlayState();
}

class _NowSignalOverlayState extends State<_NowSignalOverlay> {
  Timer? _nowTimer;

  @override
  void initState() {
    super.initState();
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final anchorDate = widget.anchorDate;
    final startHour = widget.startHour;
    final endHour = widget.endHour;
    final timeIntervalHeight = widget.timeIntervalHeight;
    final timeRulerWidth = widget.timeRulerWidth;
    final viewHeaderHeight = widget.viewHeaderHeight;
    final isRtl = widget.isRtl;
    final firstDayOfWeek = widget.firstDayOfWeek;
    final now = DateTime.now();
    final totalHours = (endHour - startHour).clamp(1, 24);
    final minutesFromStart = (now.hour * 60 + now.minute) - (startHour * 60);
    if (minutesFromStart < 0 || minutesFromStart > totalHours * 60) {
      return const SizedBox.shrink();
    }

    final top = viewHeaderHeight + (minutesFromStart / 60) * timeIntervalHeight;

    if (view == AppCalendarView.day) {
      return Stack(
        children: [
          PositionedDirectional(
            top: top,
            start: timeRulerWidth,
            end: 0,
            child: const AppSignalLine(orientation: AppSignalOrientation.horizontal, glow: true),
          ),
        ],
      );
    }

    final weekStart = _weekStart(anchorDate, firstDayOfWeek);
    final dayOffset = DateTime(now.year, now.month, now.day).difference(weekStart).inDays;
    if (dayOffset < 0 || dayOffset > 6) {
      return const SizedBox.shrink();
    }

    final columnIndex = isRtl ? 6 - dayOffset : dayOffset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - timeRulerWidth;
        final columnWidth = gridWidth / 7;
        final left = timeRulerWidth + columnWidth * columnIndex;

        return Stack(
          children: [
            Positioned(
              top: top,
              left: left,
              width: columnWidth,
              child: const AppSignalLine(orientation: AppSignalOrientation.horizontal, glow: true),
            ),
          ],
        );
      },
    );
  }
}

class _EventDetailPopover extends StatelessWidget {
  const _EventDetailPopover({required this.event, required this.conflict, required this.onDismiss});

  final AppCalendarEvent event;
  final bool conflict;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final timeLabel = _formatTimeRange(context, event.start, event.end);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(event.title, style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
              ),
              AppIconButton(
                icon: LucideIcons.x,
                semanticLabel: 'Close',
                size: AppIconButtonSize.sm,
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(timeLabel, style: typography.tabular(typography.caption.copyWith(color: colors.textSecondary))),
          if (event.subtitle != null) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(event.subtitle!, style: typography.bodySm.copyWith(color: colors.textSecondary)),
          ],
          if (conflict) ...[
            const SizedBox(height: AppSpacing.s3),
            const AppBadge(variant: AppBadgeVariant.soft, color: AppBadgeColor.danger, label: 'Scheduling conflict'),
          ],
          if (event.status != AppCalendarEventStatus.neutral) ...[
            const SizedBox(height: AppSpacing.s2),
            AppBadge(
              variant: AppBadgeVariant.soft,
              color: _badgeColor(event.status),
              label: _statusLabel(event.status),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppCalendarDataSource extends CalendarDataSource {
  _AppCalendarDataSource({
    required List<AppCalendarEvent> events,
    required Set<String> conflictIds,
    required Color fallbackColor,
    List<AppCalendarResource>? resources,
  }) {
    _eventsById = {for (final event in events) event.id: event};
    appointments = events.map((event) => _toAppointment(event, conflictIds.contains(event.id), fallbackColor)).toList();
    if (resources != null && resources.isNotEmpty) {
      this.resources = resources
          .map(
            (resource) => CalendarResource(
              id: resource.id,
              displayName: resource.displayName,
              color: resource.color ?? fallbackColor,
            ),
          )
          .toList();
    }
  }

  late Map<String, AppCalendarEvent> _eventsById;

  void update({
    required List<AppCalendarEvent> events,
    required Set<String> conflictIds,
    required Color fallbackColor,
    List<AppCalendarResource>? resources,
  }) {
    _eventsById = {for (final event in events) event.id: event};
    appointments = events.map((event) => _toAppointment(event, conflictIds.contains(event.id), fallbackColor)).toList();
    if (resources != null && resources.isNotEmpty) {
      this.resources = resources
          .map(
            (resource) => CalendarResource(
              id: resource.id,
              displayName: resource.displayName,
              color: resource.color ?? fallbackColor,
            ),
          )
          .toList();
    } else {
      this.resources = <CalendarResource>[];
    }
    notifyListeners(CalendarDataSourceAction.reset, appointments!);
  }

  AppCalendarEvent? eventFor(Object? appointment) {
    if (appointment is Appointment) {
      final id = appointment.id?.toString();
      if (id != null) return _eventsById[id];
    }
    return null;
  }

  static Appointment _toAppointment(AppCalendarEvent event, bool conflict, Color fallbackColor) {
    return Appointment(
      id: event.id,
      subject: event.title,
      startTime: event.start,
      endTime: event.end,
      isAllDay: event.allDay,
      color: conflict ? fallbackColor.withValues(alpha: 0) : (event.color ?? fallbackColor),
      resourceIds: event.resourceId != null ? <Object>[event.resourceId!] : null,
      notes: event.subtitle,
    );
  }
}

Map<ShortcutActivator, Intent> _keyboardShortcuts(bool isRtl) {
  return {
    LogicalKeySet(LogicalKeyboardKey.arrowLeft): isRtl ? const _NextIntent() : const _PreviousIntent(),
    LogicalKeySet(LogicalKeyboardKey.arrowRight): isRtl ? const _PreviousIntent() : const _NextIntent(),
    LogicalKeySet(LogicalKeyboardKey.keyT): const _TodayIntent(),
    LogicalKeySet(LogicalKeyboardKey.keyD): const _DayViewIntent(),
    LogicalKeySet(LogicalKeyboardKey.keyW): const _WeekViewIntent(),
    LogicalKeySet(LogicalKeyboardKey.keyM): const _MonthViewIntent(),
    LogicalKeySet(LogicalKeyboardKey.keyA): const _AgendaViewIntent(),
  };
}

Map<Type, Action<Intent>> _keyboardActions() {
  return {
    _PreviousIntent: CallbackAction<_PreviousIntent>(
      onInvoke: (_) {
        (_findState())?._navigate(-1);
        return null;
      },
    ),
    _NextIntent: CallbackAction<_NextIntent>(
      onInvoke: (_) {
        (_findState())?._navigate(1);
        return null;
      },
    ),
    _TodayIntent: CallbackAction<_TodayIntent>(
      onInvoke: (_) {
        (_findState())?._goToToday();
        return null;
      },
    ),
    _DayViewIntent: CallbackAction<_DayViewIntent>(
      onInvoke: (_) {
        (_findState())?._setView(AppCalendarView.day);
        return null;
      },
    ),
    _WeekViewIntent: CallbackAction<_WeekViewIntent>(
      onInvoke: (_) {
        (_findState())?._setView(AppCalendarView.week);
        return null;
      },
    ),
    _MonthViewIntent: CallbackAction<_MonthViewIntent>(
      onInvoke: (_) {
        (_findState())?._setView(AppCalendarView.month);
        return null;
      },
    ),
    _AgendaViewIntent: CallbackAction<_AgendaViewIntent>(
      onInvoke: (_) {
        (_findState())?._setView(AppCalendarView.agenda);
        return null;
      },
    ),
  };
}

_AppCalendarState? _findState() {
  return FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<_AppCalendarState>();
}

Set<String> _computeConflictIds(List<AppCalendarEvent> events) {
  final conflicts = <String>{};
  final timed = events.where((event) => !event.allDay).toList()..sort((a, b) => a.start.compareTo(b.start));

  for (var i = 0; i < timed.length; i++) {
    for (var j = i + 1; j < timed.length; j++) {
      final a = timed[i];
      final b = timed[j];
      if (!b.start.isBefore(a.end)) break;
      if (!_shareSchedulingScope(a, b)) continue;
      if (a.hasConflict == false || b.hasConflict == false) continue;
      conflicts.add(a.id);
      conflicts.add(b.id);
    }
  }

  for (final event in events) {
    if (event.hasConflict == true) conflicts.add(event.id);
  }
  return conflicts;
}

bool _shareSchedulingScope(AppCalendarEvent a, AppCalendarEvent b) {
  if (a.resourceId != null && b.resourceId != null) {
    return a.resourceId == b.resourceId;
  }
  return true;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameWeek(DateTime a, DateTime b, int firstDayOfWeek) {
  return _weekStart(a, firstDayOfWeek) == _weekStart(b, firstDayOfWeek);
}

DateTime _weekStart(DateTime date, int firstDayOfWeek) {
  final dayStart = DateTime(date.year, date.month, date.day);
  final delta = (dayStart.weekday - firstDayOfWeek + 7) % 7;
  return dayStart.subtract(Duration(days: delta));
}

String _formatTimeRange(BuildContext context, DateTime start, DateTime end) {
  final startLabel = DateFormat.jm(_AppCalendarState._westernTimeLocale).format(start.toLocal());
  final endLabel = DateFormat.jm(_AppCalendarState._westernTimeLocale).format(end.toLocal());
  return '$startLabel – $endLabel';
}

AppBadgeColor _badgeColor(AppCalendarEventStatus status) {
  return switch (status) {
    AppCalendarEventStatus.success => AppBadgeColor.success,
    AppCalendarEventStatus.warning => AppBadgeColor.warning,
    AppCalendarEventStatus.danger => AppBadgeColor.danger,
    AppCalendarEventStatus.info => AppBadgeColor.info,
    AppCalendarEventStatus.neutral => AppBadgeColor.neutral,
  };
}

String _statusLabel(AppCalendarEventStatus status) {
  return switch (status) {
    AppCalendarEventStatus.success => 'Confirmed',
    AppCalendarEventStatus.warning => 'Pending',
    AppCalendarEventStatus.danger => 'Cancelled',
    AppCalendarEventStatus.info => 'Info',
    AppCalendarEventStatus.neutral => 'Scheduled',
  };
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _TodayIntent extends Intent {
  const _TodayIntent();
}

class _DayViewIntent extends Intent {
  const _DayViewIntent();
}

class _WeekViewIntent extends Intent {
  const _WeekViewIntent();
}

class _MonthViewIntent extends Intent {
  const _MonthViewIntent();
}

class _AgendaViewIntent extends Intent {
  const _AgendaViewIntent();
}
