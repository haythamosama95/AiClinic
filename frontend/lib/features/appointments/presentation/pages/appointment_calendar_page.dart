import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:calendar_view/calendar_view.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/dev_seed_doctors_button.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
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
  int _doctorFilterReloadToken = 0;
  final EventController<AppointmentListItem> _eventController = EventController<AppointmentListItem>();
  final GlobalKey<DayViewState<AppointmentListItem>> _dayViewKey = GlobalKey<DayViewState<AppointmentListItem>>();
  final GlobalKey<WeekViewState<AppointmentListItem>> _weekViewKey = GlobalKey<WeekViewState<AppointmentListItem>>();
  int _eventsFingerprint = 0;

  @override
  Widget build(BuildContext context) {
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    _syncCalendarEvents(state.items);

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
        actions: [DevSeedDoctorsButton(onSeeded: _reloadDoctorFilter)],
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.popOrHome(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
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
              ],
            ),
            const SizedBox(height: 12),
            Text(_rangeLabel(context, state.focusDate, state.mode), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _DoctorFilter(
              selectedDoctorId: state.selectedDoctorId,
              onChanged: controller.setDoctorFilter,
              reloadToken: _doctorFilterReloadToken,
            ),
            const SizedBox(height: 16),
            if (state.loading) const Center(child: CircularProgressIndicator()),
            if (!state.loading && state.error != null) ...[
              Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: controller.refresh, child: const Text('Retry')),
            ],
            if (!state.loading && state.error == null)
              Container(
                height: 640,
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
                        )
                      : WeekView<AppointmentListItem>(
                          key: _weekViewKey,
                          controller: _eventController,
                          initialDay: state.focusDate,
                          onPageChange: (date, _) => controller.setFocusDate(date),
                          onEventTap: _onCalendarEventTap,
                          eventTileBuilder: _eventTileBuilder,
                          showWeekends: true,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _reloadDoctorFilter() {
    setState(() => _doctorFilterReloadToken++);
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
    context.nav.pushPatientDetail(item.patientId);
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

class _DoctorFilter extends ConsumerStatefulWidget {
  const _DoctorFilter({required this.selectedDoctorId, required this.onChanged, required this.reloadToken});
  final String? selectedDoctorId;
  final ValueChanged<String?> onChanged;
  final int reloadToken;

  @override
  ConsumerState<_DoctorFilter> createState() => _DoctorFilterState();
}

class _DoctorFilterState extends ConsumerState<_DoctorFilter> {
  late Future<List<StaffListItem>> _doctorsFuture = _loadDoctors();

  @override
  void didUpdateWidget(covariant _DoctorFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      setState(() {
        _doctorsFuture = _loadDoctors();
      });
    }
  }

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
