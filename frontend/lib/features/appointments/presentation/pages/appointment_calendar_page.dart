import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/syncfusion_calendar_hover_guard.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Branch appointment calendar with day, week, and month views.
class AppointmentCalendarPage extends ConsumerStatefulWidget {
  const AppointmentCalendarPage({super.key});

  @override
  ConsumerState<AppointmentCalendarPage> createState() => _AppointmentCalendarPageState();
}

class _AppointmentCalendarPageState extends ConsumerState<AppointmentCalendarPage> {
  final CalendarController _calendarController = CalendarController();
  late AppointmentCalendarDataSource _dataSource;
  AppointmentCalendarMode? _lastMode;
  DateTime? _lastSyncedFocusDate;
  int _itemsFingerprint = 0;

  @override
  void initState() {
    super.initState();
    _dataSource = AppointmentCalendarDataSource(const []);
  }

  @override
  void dispose() {
    _calendarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    if (!canAccess) {
      return const _CalendarPermissionDenied();
    }

    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final doctorsAsync = ref.watch(appointmentCalendarDoctorsProvider);
    final branches = branchesAsync.maybeWhen(data: (items) => items, orElse: () => const <BranchListItem>[]);
    final selectedBranch = branches.where((item) => item.id == state.selectedBranchId).firstOrNull;
    final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
    final visibleItems = AppointmentCalendarDisplay.filterVisibleAppointments(state.items, schedule);
    _syncDataSource(visibleItems);
    _syncCalendarView(state);

    final isClosedDay =
        state.mode == AppointmentCalendarMode.day &&
        AppointmentCalendarDisplay.isClosedOnDate(schedule, state.focusDate);

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalendarToolbar(
            branchesAsync: branchesAsync,
            doctorsAsync: doctorsAsync,
            selectedBranchId: state.selectedBranchId,
            selectedDoctorId: state.selectedDoctorId,
            onBranchChanged: controller.setBranchFilter,
            onDoctorChanged: controller.setDoctorFilter,
          ),
          const SizedBox(height: SpacingTokens.md),
          if (state.loading) const LinearProgressIndicator(minHeight: 2),
          if (!state.loading && state.error != null) ...[
            const SizedBox(height: SpacingTokens.sm),
            Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: SpacingTokens.sm),
            AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: controller.refresh),
          ],
          if (!state.loading && state.error == null && isClosedDay) ...[
            const SizedBox(height: SpacingTokens.sm),
            Text(
              'This branch is closed on ${_weekdayLabel(state.focusDate)}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotLayout = AppointmentCalendarDisplay.timeSlotLayout(
                  schedule: schedule,
                  mode: state.mode,
                  focusDate: state.focusDate,
                  viewportHeight: constraints.maxHeight,
                );
                final colors = context.semanticColors;
                final radius = BorderRadius.circular(context.shapeTokens.lg);
                return SizedBox(
                  height: constraints.maxHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.card,
                      border: Border.all(color: colors.border),
                      borderRadius: radius,
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: SyncfusionCalendarHoverGuard(
                        child: SfCalendar(
                          controller: _calendarController,
                          view: _calendarViewFor(state.mode),
                          allowedViews: const [CalendarView.day, CalendarView.week, CalendarView.month],
                          dataSource: _dataSource,
                          initialDisplayDate: state.focusDate,
                          showNavigationArrow: true,
                          showTodayButton: true,
                          showDatePickerButton: false,
                          allowViewNavigation: true,
                          blackoutDates: state.mode == AppointmentCalendarMode.month
                              ? AppointmentCalendarDisplay.closedDatesInMonth(schedule, state.focusDate)
                              : const [],
                          timeSlotViewSettings: TimeSlotViewSettings(
                            startHour: slotLayout.startHour,
                            endHour: slotLayout.endHour,
                            timeInterval: Duration(minutes: slotLayout.timeIntervalMinutes),
                            timeIntervalHeight: slotLayout.timeIntervalHeight,
                            nonWorkingDays: slotLayout.nonWorkingDays,
                            timeFormat: 'HH:mm',
                            dateFormat: 'd',
                            dayFormat: 'EEE',
                          ),
                          monthViewSettings: const MonthViewSettings(
                            showAgenda: true,
                            appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                          ),
                          specialRegions: [
                            for (final region in slotLayout.shadeRegions)
                              TimeRegion(
                                startTime: region.start,
                                endTime: region.end,
                                enablePointerInteraction: false,
                                color: colors.muted.withValues(alpha: 0.45),
                              ),
                          ],
                          appointmentBuilder: (context, details) => _AppointmentTile(
                            details: details,
                            onTap: () => _onAppointmentTileTap(details, state.items),
                          ),
                          onViewChanged: (details) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              unawaited(_onViewChanged(details, controller));
                            });
                          },
                          onTap: (details) => _onCalendarTap(details, state.items),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _syncDataSource(List<AppointmentListItem> items) {
    final fingerprint = Object.hashAll(
      items.map((item) => Object.hash(item.id, item.startTime, item.endTime, item.status)),
    );
    if (fingerprint == _itemsFingerprint) {
      return;
    }
    _itemsFingerprint = fingerprint;
    _dataSource.updateItems(items);
  }

  void _syncCalendarView(AppointmentCalendarState state) {
    final view = _calendarViewFor(state.mode);
    if (_lastMode != state.mode) {
      _lastMode = state.mode;
      _calendarController.view = view;
    }
    if (_lastSyncedFocusDate != state.focusDate) {
      _lastSyncedFocusDate = state.focusDate;
      _calendarController.displayDate = state.focusDate;
    }
  }

  Future<void> _onViewChanged(ViewChangedDetails details, AppointmentCalendarController controller) async {
    final visible = details.visibleDates;
    if (visible.isEmpty) {
      return;
    }

    final state = ref.read(appointmentCalendarProvider);
    final calendarView = _calendarController.view;
    AppointmentCalendarMode? syncedMode;
    if (calendarView != null) {
      syncedMode = _modeForCalendarView(calendarView);
      if (syncedMode != state.mode) {
        await controller.setMode(syncedMode);
      }
    }

    final anchor = visible[visible.length ~/ 2];
    final normalized = DateTime(anchor.year, anchor.month, anchor.day);
    final effectiveMode = syncedMode ?? ref.read(appointmentCalendarProvider).mode;
    if (_isSameCalendarPeriod(normalized, ref.read(appointmentCalendarProvider).focusDate, effectiveMode)) {
      return;
    }
    await controller.setFocusDate(normalized);
  }

  static bool _isSameCalendarPeriod(DateTime a, DateTime b, AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => a.year == b.year && a.month == b.month && a.day == b.day,
      AppointmentCalendarMode.week => _weekStart(a) == _weekStart(b),
      AppointmentCalendarMode.month => a.year == b.year && a.month == b.month,
    };
  }

  static DateTime _weekStart(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
  }

  void _onCalendarTap(CalendarTapDetails details, List<AppointmentListItem> items) {
    if (details.targetElement != CalendarElement.appointment) {
      return;
    }
    final id = appointmentIdFromTap(details);
    _openAppointmentById(id, items);
  }

  void _onAppointmentTileTap(CalendarAppointmentDetails details, List<AppointmentListItem> items) {
    _openAppointmentById(appointmentIdFromAppointmentDetails(details), items);
  }

  void _openAppointmentById(String? id, List<AppointmentListItem> items) {
    if (id == null) {
      return;
    }
    final item = items.where((entry) => entry.id == id).firstOrNull;
    if (item == null) {
      return;
    }
    unawaited(_showAppointmentSheet(item));
  }

  Future<void> _showAppointmentSheet(AppointmentListItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = sheetContext.semanticColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.sm, SpacingTokens.lg, SpacingTokens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.patientName, style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: SpacingTokens.xs),
              Text(item.doctorDisplayName, style: Theme.of(sheetContext).textTheme.bodyMedium),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                _formatRange(item.startTime, item.endTime),
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(item.status.label, style: Theme.of(sheetContext).textTheme.labelLarge),
              const SizedBox(height: SpacingTokens.lg),
              AppButton(
                label: 'Open patient',
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  AppNavigator(context).pushPatientDetail(item.patientId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static CalendarView _calendarViewFor(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => CalendarView.day,
      AppointmentCalendarMode.week => CalendarView.week,
      AppointmentCalendarMode.month => CalendarView.month,
    };
  }

  static AppointmentCalendarMode _modeForCalendarView(CalendarView view) {
    return switch (view) {
      CalendarView.day => AppointmentCalendarMode.day,
      CalendarView.week => AppointmentCalendarMode.week,
      CalendarView.month => AppointmentCalendarMode.month,
      _ => AppointmentCalendarMode.week,
    };
  }

  static String _weekdayLabel(DateTime date) => DateFormat.EEEE().format(date);

  static String _formatRange(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final day = DateFormat.yMMMd().format(localStart);
    final from = DateFormat.Hm().format(localStart);
    final to = DateFormat.Hm().format(localEnd);
    return '$day · $from – $to';
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.selectedBranchId,
    required this.selectedDoctorId,
    required this.onBranchChanged,
    required this.onDoctorChanged,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? selectedBranchId;
  final String? selectedDoctorId;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onDoctorChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: branchesAsync.when(
              data: (items) => AppFilterSelect<String?>(
                label: 'Branch',
                items: {for (final branch in items) branch.name: branch.id},
                value: selectedBranchId,
                hintText: items.isEmpty ? 'No branches' : 'Select branch',
                enabled: items.isNotEmpty,
                onChanged: items.isEmpty ? null : onBranchChanged,
              ),
              loading: () => const Text('Loading branches…'),
              error: (_, _) => const Text('Could not load branches.'),
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          SizedBox(
            width: 200,
            child: doctorsAsync.when(
              data: (doctors) => AppFilterSelect<String>(
                label: 'Doctor',
                items: {'All doctors': '', for (final doctor in doctors) doctor.fullName: doctor.id},
                value: selectedDoctorId ?? '',
                onChanged: (doctorId) => onDoctorChanged(doctorId == null || doctorId.isEmpty ? null : doctorId),
              ),
              loading: () => const Text('Loading doctors…'),
              error: (_, _) => const Text('Could not load doctors.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.details, required this.onTap});

  final CalendarAppointmentDetails details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appointment = details.appointments.first;
    final brightness = ThemeData.estimateBrightnessForColor(appointment.color);
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
        decoration: BoxDecoration(
          color: appointment.color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: appointment.color),
        ),
        alignment: Alignment.topLeft,
        child: Text(
          appointment.notes == null || appointment.notes!.isEmpty
              ? appointment.subject
              : '${appointment.subject}\n${appointment.notes}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2, color: textColor),
        ),
      ),
    );
  }
}

class _CalendarPermissionDenied extends StatelessWidget {
  const _CalendarPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Text(
          'You do not have permission to view appointments.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
