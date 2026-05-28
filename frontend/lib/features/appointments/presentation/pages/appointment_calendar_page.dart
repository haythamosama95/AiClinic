import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_view/calendar_view.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

class AppointmentCalendarPage extends ConsumerStatefulWidget {
  const AppointmentCalendarPage({super.key});

  @override
  ConsumerState<AppointmentCalendarPage> createState() => _AppointmentCalendarPageState();
}

class _AppointmentCalendarPageState extends ConsumerState<AppointmentCalendarPage> {
  static const double _calendarViewportHeight = 640;
  final ScrollController _pageScrollController = ScrollController();
  final EventController<AppointmentListItem> _eventController = EventController<AppointmentListItem>();
  final GlobalKey<DayViewState<AppointmentListItem>> _dayViewKey = GlobalKey<DayViewState<AppointmentListItem>>();
  final GlobalKey<WeekViewState<AppointmentListItem>> _weekViewKey = GlobalKey<WeekViewState<AppointmentListItem>>();
  int _eventsFingerprint = 0;

  @override
  void dispose() {
    _pageScrollController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final branchesAsync = ref.watch(_calendarBranchesProvider);
    final branches = branchesAsync.maybeWhen(data: (items) => items, orElse: () => const <BranchListItem>[]);
    final selectedBranch = branches.where((item) => item.id == state.selectedBranchId).firstOrNull;
    final selectedSchedule = (selectedBranch?.id.isNotEmpty ?? false)
        ? selectedBranch!.workingSchedule
        : BranchWorkingSchedule.defaultSchedule();
    final visibleItems = _filterItemsBySchedule(state.items, selectedSchedule);
    _syncCalendarEvents(visibleItems);
    final (startHour, endHour) = _calendarHourRangeFor(selectedSchedule);
    final heightPerMinute = _heightPerMinuteForRange(startHour: startHour, endHour: endHour);
    final showWeekends = _showWeekendsFor(selectedSchedule);
    final isClosedOnFocusDay =
        state.mode == AppointmentCalendarMode.day &&
        !_isWorkingDay(selectedSchedule, _weekdayFromDate(state.focusDate));

    if (!canAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Appointment calendar')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view appointments.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment calendar'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.popOrHome(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          controller: _pageScrollController,
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<AppointmentCalendarMode>(
                  segments: const [
                    ButtonSegment(value: AppointmentCalendarMode.day, label: Text('Day')),
                    ButtonSegment(value: AppointmentCalendarMode.week, label: Text('Week')),
                  ],
                  selected: {state.mode},
                  onSelectionChanged: (selection) => controller.setMode(selection.first),
                ),
                OutlinedButton.icon(
                  key: const Key('appointments_calendar_prev'),
                  onPressed: () => _goToPreviousPeriod(controller, state.mode),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                OutlinedButton.icon(
                  key: const Key('appointments_calendar_next'),
                  onPressed: () => _goToNextPeriod(controller, state.mode),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
                FilledButton.tonal(
                  key: const Key('appointments_calendar_today'),
                  onPressed: () => _jumpToToday(controller, state.mode),
                  child: const Text('Today'),
                ),
                SizedBox(
                  width: 240,
                  child: branchesAsync.when(
                    data: (branches) => DropdownButtonFormField<String?>(
                      key: const Key('appointments_calendar_branch_filter'),
                      initialValue: state.selectedBranchId,
                      decoration: const InputDecoration(labelText: 'Branch'),
                      items: [
                        if (branches.isEmpty) const DropdownMenuItem<String?>(value: null, child: Text('No branches')),
                        for (final branch in branches)
                          DropdownMenuItem<String?>(value: branch.id, child: Text(branch.name)),
                      ],
                      onChanged: branches.isEmpty ? null : controller.setBranchFilter,
                    ),
                    loading: () => const InputDecorator(
                      decoration: InputDecoration(labelText: 'Branch'),
                      child: Text('Loading branches...'),
                    ),
                    error: (_, _) => const InputDecorator(
                      decoration: InputDecoration(labelText: 'Branch'),
                      child: Text('Could not load branches.'),
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: _DoctorFilter(selectedDoctorId: state.selectedDoctorId, onChanged: controller.setDoctorFilter),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_rangeLabel(context, state.focusDate, state.mode), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (state.loading) const Center(child: CircularProgressIndicator()),
            if (!state.loading && state.error != null) ...[
              Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: controller.refresh, child: const Text('Retry')),
            ],
            if (!state.loading && state.error == null && isClosedOnFocusDay) ...[
              Text(
                'This branch is closed on ${_weekdayFromDate(state.focusDate).label}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            if (!state.loading && state.error == null)
              Container(
                height: _calendarViewportHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: state.mode == AppointmentCalendarMode.day
                      ? DayView<AppointmentListItem>(
                          key: _dayViewKey,
                          controller: _eventController,
                          initialDay: state.focusDate,
                          onPageChange: (date, _) => controller.setFocusDate(date),
                          onEventTap: _onCalendarEventTap,
                          eventTileBuilder: _eventTileBuilder,
                          startHour: startHour,
                          endHour: endHour,
                          heightPerMinute: heightPerMinute,
                        )
                      : WeekView<AppointmentListItem>(
                          key: _weekViewKey,
                          controller: _eventController,
                          initialDay: state.focusDate,
                          onPageChange: (date, _) => controller.setFocusDate(date),
                          onEventTap: _onCalendarEventTap,
                          eventTileBuilder: _eventTileBuilder,
                          showWeekends: showWeekends,
                          startHour: startHour,
                          endHour: endHour,
                          heightPerMinute: heightPerMinute,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<AppointmentListItem> _filterItemsBySchedule(List<AppointmentListItem> items, BranchWorkingSchedule? schedule) {
    if (schedule == null) {
      return items;
    }
    return items
        .where((item) {
          final localStart = item.startTime.toLocal();
          final localEnd = item.endTime.toLocal();
          final weekday = _weekdayFromDate(localStart);
          final dayHours = _hoursForDay(schedule, weekday);
          if (dayHours == null || !dayHours.isWorkingDay) {
            return false;
          }
          final openMinutes = _parseHm(dayHours.openTime);
          final closeMinutes = _parseHm(dayHours.closeTime);
          if (openMinutes == null || closeMinutes == null) {
            return false;
          }
          final startMinutes = localStart.hour * 60 + localStart.minute;
          final endMinutes = localEnd.hour * 60 + localEnd.minute;
          return startMinutes >= openMinutes && endMinutes <= closeMinutes;
        })
        .toList(growable: false);
  }

  (int, int) _calendarHourRangeFor(BranchWorkingSchedule? schedule) {
    if (schedule == null) {
      return (8, 18);
    }
    var minMinutes = 24 * 60;
    var maxMinutes = 0;
    for (final day in schedule.days) {
      if (!day.isWorkingDay) {
        continue;
      }
      final open = _parseHm(day.openTime);
      final close = _parseHm(day.closeTime);
      if (open == null || close == null || open >= close) {
        continue;
      }
      if (open < minMinutes) {
        minMinutes = open;
      }
      if (close > maxMinutes) {
        maxMinutes = close;
      }
    }
    if (minMinutes == 24 * 60 || maxMinutes == 0) {
      return (8, 18);
    }
    final startHour = (minMinutes ~/ 60).clamp(0, 23);
    var endHour = ((maxMinutes + 59) ~/ 60).clamp(1, 24);
    if (endHour <= startHour) {
      endHour = (startHour + 1).clamp(1, 24);
    }
    return (startHour, endHour);
  }

  double _heightPerMinuteForRange({required int startHour, required int endHour}) {
    final totalMinutes = ((endHour - startHour) * 60).clamp(60, 24 * 60);
    return _calendarViewportHeight / totalMinutes;
  }

  bool _showWeekendsFor(BranchWorkingSchedule? schedule) {
    if (schedule == null) {
      return true;
    }
    final saturdayWorking = _isWorkingDay(schedule, BranchWeekday.saturday);
    final sundayWorking = _isWorkingDay(schedule, BranchWeekday.sunday);
    return saturdayWorking || sundayWorking;
  }

  bool _isWorkingDay(BranchWorkingSchedule? schedule, BranchWeekday weekday) {
    final day = _hoursForDay(schedule, weekday);
    return day?.isWorkingDay ?? false;
  }

  BranchWorkingDayHours? _hoursForDay(BranchWorkingSchedule? schedule, BranchWeekday weekday) {
    if (schedule == null) {
      return null;
    }
    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day;
      }
    }
    return null;
  }

  BranchWeekday _weekdayFromDate(DateTime date) {
    return switch (date.weekday) {
      DateTime.monday => BranchWeekday.monday,
      DateTime.tuesday => BranchWeekday.tuesday,
      DateTime.wednesday => BranchWeekday.wednesday,
      DateTime.thursday => BranchWeekday.thursday,
      DateTime.friday => BranchWeekday.friday,
      DateTime.saturday => BranchWeekday.saturday,
      _ => BranchWeekday.sunday,
    };
  }

  int? _parseHm(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  void _syncCalendarEvents(List<AppointmentListItem> items) {
    final fingerprint = Object.hashAll(
      items.map((item) => Object.hash(item.id, item.startTime, item.endTime, item.status, item.type)),
    );
    if (fingerprint == _eventsFingerprint) {
      return;
    }

    _eventsFingerprint = fingerprint;
    _eventController
      ..clear()
      ..addAll(
        items
            .map(
              (item) => CalendarEventData<AppointmentListItem>(
                date: item.startTime.toLocal(),
                startTime: item.startTime.toLocal(),
                endTime: item.endTime.toLocal(),
                title: item.patientName,
                description: item.doctorDisplayName,
                color: _statusColor(item.status),
                event: item,
              ),
            )
            .toList(growable: false),
      );
  }

  Future<void> _goToPreviousPeriod(AppointmentCalendarController controller, AppointmentCalendarMode mode) async {
    await controller.previousPeriod();
    final focusDate = ref.read(appointmentCalendarProvider).focusDate;
    if (mode == AppointmentCalendarMode.day) {
      _dayViewKey.currentState?.animateToDate(focusDate);
    } else {
      _weekViewKey.currentState?.animateToWeek(focusDate);
    }
  }

  Future<void> _goToNextPeriod(AppointmentCalendarController controller, AppointmentCalendarMode mode) async {
    await controller.nextPeriod();
    final focusDate = ref.read(appointmentCalendarProvider).focusDate;
    if (mode == AppointmentCalendarMode.day) {
      _dayViewKey.currentState?.animateToDate(focusDate);
    } else {
      _weekViewKey.currentState?.animateToWeek(focusDate);
    }
  }

  void _jumpToToday(AppointmentCalendarController controller, AppointmentCalendarMode mode) {
    final today = DateTime.now();
    if (mode == AppointmentCalendarMode.day) {
      _dayViewKey.currentState?.animateToDate(today);
    } else {
      _weekViewKey.currentState?.animateToWeek(today);
    }
    controller.setFocusDate(today);
  }

  void _onCalendarEventTap(List<CalendarEventData<AppointmentListItem>> events, DateTime date) {
    if (events.isEmpty) {
      return;
    }
    final item = events.first.event;
    if (item == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _AppointmentEventSheet(
        item: item,
        onStatusChanged: () {
          Navigator.of(sheetContext).pop();
          ref.read(appointmentCalendarProvider.notifier).refresh();
        },
        onOpenPatient: () {
          Navigator.of(sheetContext).pop();
          context.nav.pushPatientDetail(item.patientId);
        },
      ),
    );
  }

  Widget _eventTileBuilder(
    DateTime date,
    List<CalendarEventData<AppointmentListItem>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    final event = events.first;
    final item = event.event;
    final subtitle = item == null ? '' : item.doctorDisplayName;
    final tileColor = event.color;
    final brightness = ThemeData.estimateBrightnessForColor(tileColor);
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tileColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tileColor.withValues(alpha: 0.95), width: 1.1),
      ),
      child: Text(
        subtitle.isEmpty ? event.title : '${event.title}\n$subtitle',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
      ),
    );
  }

  Color _statusColor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => Colors.blue,
      AppointmentStatus.confirmed => Colors.teal,
      AppointmentStatus.checkedIn => Colors.cyan,
      AppointmentStatus.inProgress => Colors.orange,
      AppointmentStatus.completed => Colors.green,
      AppointmentStatus.cancelled => Colors.red,
      AppointmentStatus.noShow => Colors.deepPurple,
    };
  }

  String _rangeLabel(BuildContext context, DateTime focus, AppointmentCalendarMode mode) {
    final localizations = MaterialLocalizations.of(context);
    final day = DateTime(focus.year, focus.month, focus.day);
    if (mode == AppointmentCalendarMode.day) {
      return localizations.formatFullDate(day);
    }
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return '${localizations.formatMediumDate(start)} - ${localizations.formatMediumDate(end)}';
  }
}

class _AppointmentEventSheet extends StatelessWidget {
  const _AppointmentEventSheet({required this.item, required this.onStatusChanged, required this.onOpenPatient});

  final AppointmentListItem item;
  final VoidCallback onStatusChanged;
  final VoidCallback onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final localStart = item.startTime.toLocal();
    final localEnd = item.endTime.toLocal();
    final timeRange =
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localStart))} – '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localEnd))}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.patientName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${item.doctorDisplayName} · ${item.type.label} · ${item.status.label}'),
            const SizedBox(height: 4),
            Text(timeRange),
            const SizedBox(height: 16),
            AppointmentStatusActions(
              item: item,
              onStatusChanged: (_) => onStatusChanged(),
              onRescheduled: (_) => onStatusChanged(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onOpenPatient, child: const Text('Open patient record')),
            ),
          ],
        ),
      ),
    );
  }
}

final _calendarBranchesProvider = FutureProvider.autoDispose<List<BranchListItem>>((ref) async {
  final auth = ref.read(authSessionProvider).context;
  final orgId = auth?.organizationId;
  if (orgId == null || orgId.trim().isEmpty) {
    return const <BranchListItem>[];
  }
  final branches = await ref.read(listBranchesUseCaseProvider)(organizationId: orgId, filter: BranchListFilter.active);
  return branches..sort((a, b) => a.name.compareTo(b.name));
});

class _DoctorFilter extends ConsumerStatefulWidget {
  const _DoctorFilter({required this.selectedDoctorId, required this.onChanged});
  final String? selectedDoctorId;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_DoctorFilter> createState() => _DoctorFilterState();
}

class _DoctorFilterState extends ConsumerState<_DoctorFilter> {
  late Future<List<StaffListItem>> _doctorsFuture = _loadDoctors();

  Future<List<StaffListItem>> _loadDoctors() async {
    final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
    return staff.where((item) => item.role == StaffRole.doctor && item.isActive).toList(growable: false)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StaffListItem>>(
      future: _doctorsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InputDecorator(
            decoration: InputDecoration(labelText: 'Doctor filter'),
            child: Text('Loading doctors...'),
          );
        }
        if (snapshot.hasError) {
          return const InputDecorator(
            decoration: InputDecoration(labelText: 'Doctor filter'),
            child: Text('Could not load doctors.'),
          );
        }
        final doctors = snapshot.data ?? const <StaffListItem>[];
        return DropdownButtonFormField<String?>(
          key: const Key('appointments_calendar_doctor_filter'),
          initialValue: widget.selectedDoctorId,
          decoration: const InputDecoration(labelText: 'Doctor filter'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All doctors')),
            for (final doctor in doctors) DropdownMenuItem<String?>(value: doctor.id, child: Text(doctor.fullName)),
          ],
          onChanged: widget.onChanged,
        );
      },
    );
  }
}
