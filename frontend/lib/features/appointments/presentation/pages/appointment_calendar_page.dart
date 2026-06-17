import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_header_bar.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_skeleton.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

const _skeletonRevealDelay = Duration(milliseconds: 180);

/// Resource row height in the doctor timeline view; must match [TimeSlotViewSettings.timelineAppointmentHeight].
const _timelineResourceRowHeight = 120.0;

/// Branch appointment calendar with day, week, month, schedule, and doctor timeline views.
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
  int _resourceFingerprint = 0;
  Set<String> _revealedAppointmentIds = {};
  int _revealGeneration = 0;
  int _lastRevealSourceFingerprint = -1;
  bool _isProcessingDrag = false;
  _CalendarDragSession? _dragSession;
  _CalendarResizeSession? _resizeSession;

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
    final colors = context.semanticColors;
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    if (!canAccess) {
      return const _CalendarPermissionDenied();
    }

    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final authState = ref.watch(authSessionProvider);
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final doctorsAsync = ref.watch(appointmentCalendarDoctorsProvider);
    final branches = branchesAsync.maybeWhen(data: (items) => items, orElse: () => const <BranchListItem>[]);
    final selectedBranch = branches.where((item) => item.id == state.selectedBranchId).firstOrNull;
    final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
    final visibleItems = AppointmentCalendarDisplay.filterVisibleAppointments(state.items, schedule);
    final allDoctors = doctorsAsync.maybeWhen(data: (items) => items, orElse: () => const <StaffListItem>[]);
    final doctors = _filteredDoctors(allDoctors, selectedDoctorId: state.selectedDoctorId, mode: state.mode);
    final hasActiveFilters = state.hasActiveFilters(initialBranchId: authState.context?.activeBranchId);
    final canCreate = ref.watch(permissionServiceProvider).canCreateAppointments();
    final oddResourceRowColor = colors.muted.withValues(alpha: 0.3);
    _scheduleRevealIfNeeded(visibleItems, loading: state.loading);
    if (!state.loading) {
      if (_dragSession == null && _resizeSession == null) {
        _syncDataSource(
          visibleItems,
          doctors: doctors,
          includeDoctorResources: _usesDoctorResources(state.mode),
          evenResourceRowColor: colors.background,
          oddResourceRowColor: oddResourceRowColor,
        );
      }
      _syncCalendarView(state);
    }

    final isClosedDay =
        (state.mode == AppointmentCalendarMode.day || state.mode == AppointmentCalendarMode.doctors) &&
        AppointmentCalendarDisplay.isClosedOnDate(schedule, state.focusDate);

    return Material(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!state.loading && state.error != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.sm, SpacingTokens.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: SpacingTokens.sm),
                  AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: controller.refresh),
                ],
              ),
            ),
          ],
          if (!state.loading && state.error == null && isClosedDay)
            Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.sm, SpacingTokens.lg, 0),
              child: Text(
                'This branch is closed on ${_weekdayLabel(state.focusDate)}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: constraints.maxHeight,
                  child: _buildCalendar(
                    context: context,
                    colors: colors,
                    state: state,
                    controller: controller,
                    branchesAsync: branchesAsync,
                    doctorsAsync: doctorsAsync,
                    schedule: schedule,
                    doctors: doctors,
                    canCreate: canCreate,
                    visibleItems: visibleItems,
                    oddResourceRowColor: oddResourceRowColor,
                    loading: state.loading,
                    viewportHeight: constraints.maxHeight - appointmentCalendarHeaderHeight,
                    hasActiveFilters: hasActiveFilters,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar({
    required BuildContext context,
    required SemanticColors colors,
    required AppointmentCalendarState state,
    required AppointmentCalendarController controller,
    required AsyncValue<List<BranchListItem>> branchesAsync,
    required AsyncValue<List<StaffListItem>> doctorsAsync,
    required BranchWorkingSchedule schedule,
    required List<StaffListItem> doctors,
    required bool canCreate,
    required List<AppointmentListItem> visibleItems,
    required Color oddResourceRowColor,
    required bool loading,
    required double viewportHeight,
    required bool hasActiveFilters,
  }) {
    final slotLayout = AppointmentCalendarDisplay.timeSlotLayout(
      schedule: schedule,
      mode: state.mode,
      focusDate: state.focusDate,
      viewportHeight: viewportHeight,
    );
    final textTheme = Theme.of(context).textTheme;
    final pageBackground = colors.background;
    final allowDragAndDrop = canCreate && _supportsDragAndDrop(state.mode);
    final calendarTheme = SfCalendarThemeData(
      backgroundColor: pageBackground,
      headerBackgroundColor: pageBackground,
      viewHeaderBackgroundColor: pageBackground,
      agendaBackgroundColor: pageBackground,
      allDayPanelColor: pageBackground,
      cellBorderColor: colors.border,
      headerTextStyle: textTheme.titleMedium?.copyWith(color: colors.foreground),
      viewHeaderDayTextStyle: textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
      viewHeaderDateTextStyle: textTheme.labelMedium?.copyWith(color: colors.foreground),
      timeTextStyle: textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
      todayHighlightColor: colors.primary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppointmentCalendarHeaderBar(
          branchesAsync: branchesAsync,
          doctorsAsync: doctorsAsync,
          appliedBranchId: state.selectedBranchId,
          appliedDoctorId: state.selectedDoctorId,
          showDoctorFilter: true,
          hasActiveFilters: hasActiveFilters,
          onApplyFilters: (filters) => controller.applyFilters(branchId: filters.branchId, doctorId: filters.doctorId),
          onClearFilters: controller.clearFilters,
          onBookAppointment: canCreate && state.selectedBranchId != null && state.selectedBranchId!.isNotEmpty
              ? () {
                  final slotRange = AppointmentCalendarDisplay.slotRangeFromTap(
                    tappedDate: state.focusDate,
                    schedule: schedule,
                    mode: state.mode,
                    slotMinutes: slotLayout.timeIntervalMinutes,
                  );
                  unawaited(
                    _showBookingSheet(
                      branchId: state.selectedBranchId!,
                      schedule: schedule,
                      slotStart: slotRange.start,
                      slotEnd: slotRange.end,
                      initialDoctorId: state.selectedDoctorId,
                      doctors: doctors,
                    ),
                  );
                }
              : null,
        ),
        Expanded(
          child: loading
              ? const AppointmentCalendarSkeleton()
              : SfCalendarTheme(
                  data: calendarTheme,
                  child: SfCalendar(
                    controller: _calendarController,
                    view: _calendarViewFor(state.mode),
                    allowedViews: const [
                      CalendarView.day,
                      CalendarView.week,
                      CalendarView.month,
                      CalendarView.schedule,
                      CalendarView.timelineDay,
                    ],
                    dataSource: _dataSource,
                    initialDisplayDate: state.focusDate,
                    backgroundColor: pageBackground,
                    cellBorderColor: colors.border,
                    headerHeight: 0,
                    resourceViewSettings: ResourceViewSettings(
                      showAvatar: false,
                      size: _timelineResourceRowHeight,
                      visibleResourceCount: -1,
                      displayNameTextStyle: textTheme.labelMedium?.copyWith(color: colors.foreground),
                    ),
                    showNavigationArrow: false,
                    showTodayButton: false,
                    showDatePickerButton: false,
                    allowViewNavigation: false,
                    headerStyle: CalendarHeaderStyle(
                      backgroundColor: pageBackground,
                      textStyle: textTheme.titleMedium?.copyWith(color: colors.foreground),
                    ),
                    viewHeaderStyle: ViewHeaderStyle(backgroundColor: pageBackground),
                    selectionDecoration: const BoxDecoration(
                      color: Colors.transparent,
                      border: Border.fromBorderSide(BorderSide(color: Colors.transparent, width: 0)),
                    ),
                    blackoutDates: state.mode == AppointmentCalendarMode.month
                        ? AppointmentCalendarDisplay.closedDatesInMonth(schedule, state.focusDate)
                        : const [],
                    timeSlotViewSettings: TimeSlotViewSettings(
                      startHour: slotLayout.startHour,
                      endHour: slotLayout.endHour,
                      timeInterval: Duration(minutes: slotLayout.timeIntervalMinutes),
                      timeIntervalHeight: slotLayout.timeIntervalHeight,
                      timelineAppointmentHeight: _timelineResourceRowHeight,
                      nonWorkingDays: slotLayout.nonWorkingDays,
                      timeFormat: 'HH:mm',
                      dateFormat: 'd',
                      dayFormat: 'EEE',
                    ),
                    monthViewSettings: const MonthViewSettings(
                      showAgenda: true,
                      appointmentDisplayMode: MonthAppointmentDisplayMode.indicator,
                    ),
                    scheduleViewSettings: const ScheduleViewSettings(appointmentItemHeight: 52),
                    specialRegions: [
                      for (final region in slotLayout.shadeRegions)
                        TimeRegion(
                          startTime: region.start,
                          endTime: region.end,
                          enablePointerInteraction: false,
                          color: colors.muted.withValues(alpha: 0.45),
                        ),
                      if (state.mode == AppointmentCalendarMode.doctors)
                        ...AppointmentCalendarDisplay.resourceRowStripeRegions(
                          resourceIds: [
                            for (final resource in _dataSource.resources ?? const <CalendarResource>[]) resource.id,
                          ],
                          focusDate: state.focusDate,
                          startHour: slotLayout.startHour,
                          endHour: slotLayout.endHour,
                          stripeColor: oddResourceRowColor,
                        ),
                    ],
                    appointmentBuilder: (context, details) {
                      final id = appointmentIdFromAppointmentDetails(details);
                      if (id != null &&
                          (_dragSession?.item.id == id || _resizeSession?.item.id == id) &&
                          !AppointmentCalendarDisplay.isAlignedToSlotGrid(
                            details.bounds,
                            slotLayout.timeIntervalHeight,
                            timelineAxisIsHorizontal: state.mode == AppointmentCalendarMode.doctors,
                          )) {
                        return const SizedBox.shrink();
                      }
                      final isRevealed = id == null || _revealedAppointmentIds.contains(id);
                      return Skeletonizer(
                        enabled: !isRevealed,
                        enableSwitchAnimation: true,
                        effect: ShimmerEffect(
                          baseColor: colors.muted,
                          highlightColor: colors.muted.withValues(alpha: 0.55),
                        ),
                        containersColor: colors.muted,
                        child: _AppointmentTile(
                          details: details,
                          onTap: isRevealed ? () => _onAppointmentTileTap(details, state.items) : () {},
                        ),
                      );
                    },
                    onViewChanged: (details) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        unawaited(_onViewChanged(details, controller));
                      });
                    },
                    allowDragAndDrop: allowDragAndDrop,
                    allowAppointmentResize: allowDragAndDrop,
                    dragAndDropSettings: const DragAndDropSettings(showTimeIndicator: false),
                    onDragStart: allowDragAndDrop
                        ? (details) => _onAppointmentDragStart(
                            details,
                            items: visibleItems,
                            slotMinutes: slotLayout.timeIntervalMinutes,
                            doctors: doctors,
                            includeDoctorResources: _usesDoctorResources(state.mode),
                            evenResourceRowColor: colors.background,
                            oddResourceRowColor: oddResourceRowColor,
                          )
                        : null,
                    onDragUpdate: allowDragAndDrop
                        ? (details) => _onAppointmentDragUpdate(
                            details,
                            slotMinutes: slotLayout.timeIntervalMinutes,
                            doctors: doctors,
                            includeDoctorResources: _usesDoctorResources(state.mode),
                            evenResourceRowColor: colors.background,
                            oddResourceRowColor: oddResourceRowColor,
                          )
                        : null,
                    onTap: (details) {
                      _onCalendarSelectionTap(details, state.mode);
                      _onCalendarTap(
                        details,
                        state.items,
                        branchId: state.selectedBranchId,
                        schedule: schedule,
                        mode: state.mode,
                        slotMinutes: slotLayout.timeIntervalMinutes,
                        doctors: doctors,
                        canCreate: canCreate,
                      );
                    },
                    onDragEnd: allowDragAndDrop
                        ? (details) {
                            unawaited(
                              _onAppointmentDragEnd(
                                details,
                                items: visibleItems,
                                schedule: schedule,
                                mode: state.mode,
                                slotMinutes: slotLayout.timeIntervalMinutes,
                                doctors: doctors,
                                includeDoctorResources: _usesDoctorResources(state.mode),
                                evenResourceRowColor: colors.background,
                                oddResourceRowColor: oddResourceRowColor,
                              ),
                            );
                          }
                        : null,
                    onAppointmentResizeStart: allowDragAndDrop
                        ? (details) => _onAppointmentResizeStart(
                            details,
                            items: visibleItems,
                            slotMinutes: slotLayout.timeIntervalMinutes,
                            doctors: doctors,
                            includeDoctorResources: _usesDoctorResources(state.mode),
                            evenResourceRowColor: colors.background,
                            oddResourceRowColor: oddResourceRowColor,
                          )
                        : null,
                    onAppointmentResizeUpdate: allowDragAndDrop
                        ? (details) => _onAppointmentResizeUpdate(
                            details,
                            slotMinutes: slotLayout.timeIntervalMinutes,
                            doctors: doctors,
                            includeDoctorResources: _usesDoctorResources(state.mode),
                            evenResourceRowColor: colors.background,
                            oddResourceRowColor: oddResourceRowColor,
                          )
                        : null,
                    onAppointmentResizeEnd: allowDragAndDrop
                        ? (details) {
                            unawaited(
                              _onAppointmentResizeEnd(
                                details,
                                items: visibleItems,
                                schedule: schedule,
                                slotMinutes: slotLayout.timeIntervalMinutes,
                                doctors: doctors,
                                includeDoctorResources: _usesDoctorResources(state.mode),
                                evenResourceRowColor: colors.background,
                                oddResourceRowColor: oddResourceRowColor,
                              ),
                            );
                          }
                        : null,
                  ),
                ),
        ),
      ],
    );
  }

  void _scheduleRevealIfNeeded(List<AppointmentListItem> items, {required bool loading}) {
    if (loading) {
      if (_revealedAppointmentIds.isEmpty && _lastRevealSourceFingerprint == -1) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _revealedAppointmentIds = {};
          _lastRevealSourceFingerprint = -1;
          _revealGeneration++;
        });
      });
      return;
    }

    final sourceFingerprint = Object.hashAll(items.map((item) => item.id));
    if (sourceFingerprint == _lastRevealSourceFingerprint) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _lastRevealSourceFingerprint = sourceFingerprint;
      _startSkeletonReveal(items.map((item) => item.id).toList(growable: false));
    });
  }

  void _startSkeletonReveal(List<String> appointmentIds) {
    _revealGeneration++;
    final generation = _revealGeneration;

    setState(() => _revealedAppointmentIds = {});

    if (appointmentIds.isEmpty) {
      return;
    }

    Future<void>.delayed(_skeletonRevealDelay, () {
      if (!mounted || generation != _revealGeneration) {
        return;
      }
      setState(() => _revealedAppointmentIds = appointmentIds.toSet());
    });
  }

  void _syncDataSource(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final itemsFingerprint = Object.hashAll(
      items.map(
        (item) => Object.hash(
          item.id,
          item.startTime,
          item.endTime,
          item.status,
          item.doctorId,
          item.patientName,
          item.doctorName,
        ),
      ),
    );
    final resourceFingerprint = Object.hash(
      includeDoctorResources,
      Object.hashAll(doctors.map((doctor) => doctor.id)),
      evenResourceRowColor,
      oddResourceRowColor,
    );
    if (itemsFingerprint == _itemsFingerprint && resourceFingerprint == _resourceFingerprint) {
      return;
    }
    _itemsFingerprint = itemsFingerprint;
    _resourceFingerprint = resourceFingerprint;
    _dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
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
      AppointmentCalendarMode.doctors => a.year == b.year && a.month == b.month && a.day == b.day,
      AppointmentCalendarMode.week => _weekStart(a) == _weekStart(b),
      AppointmentCalendarMode.schedule => _weekStart(a) == _weekStart(b),
      AppointmentCalendarMode.month => a.year == b.year && a.month == b.month,
    };
  }

  static DateTime _weekStart(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
  }

  void _onAppointmentDragStart(
    AppointmentDragStartDetails details, {
    required List<AppointmentListItem> items,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final calendarAppointment = details.appointment;
    if (calendarAppointment is! Appointment) {
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      return;
    }

    final item = items.where((entry) => entry.id == appointmentId).firstOrNull;
    if (item == null) {
      return;
    }

    setState(() {
      _dragSession = _CalendarDragSession(
        item: item,
        previewStart: item.startTime.toLocal(),
        slotMinutes: slotMinutes,
        baseItems: items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
    });
    _applyDragPreview(_dragSession!);
  }

  void _onAppointmentDragUpdate(
    AppointmentDragUpdateDetails details, {
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final session = _dragSession;
    final draggingTime = details.draggingTime;
    if (session == null || draggingTime == null) {
      return;
    }

    final snappedStart = AppointmentCalendarDisplay.snapTimeToSlot(draggingTime, slotMinutes: slotMinutes);
    if (snappedStart == session.previewStart) {
      return;
    }

    session.previewStart = snappedStart;
    session
      ..doctors = doctors
      ..includeDoctorResources = includeDoctorResources
      ..evenResourceRowColor = evenResourceRowColor
      ..oddResourceRowColor = oddResourceRowColor;
    _applyDragPreview(session);
  }

  void _applyDragPreview(_CalendarDragSession session) {
    final duration = session.item.endTime.difference(session.item.startTime);
    final previewEnd = session.previewStart.add(duration);
    final previewItems = [
      for (final entry in session.baseItems)
        if (entry.id == session.item.id)
          entry.copyWith(startTime: session.previewStart, endTime: previewEnd)
        else
          entry,
    ];
    _revertCalendarItems(
      previewItems,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
  }

  void _clearDragSession({required List<AppointmentListItem> items}) {
    final session = _dragSession;
    if (session == null) {
      return;
    }

    _revertCalendarItems(
      items,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
    setState(() => _dragSession = null);
  }

  Future<void> _onAppointmentDragEnd(
    AppointmentDragEndDetails details, {
    required List<AppointmentListItem> items,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) async {
    if (_isProcessingDrag) {
      return;
    }

    final session = _dragSession;
    final droppingTime = details.droppingTime;
    final calendarAppointment = details.appointment;
    if (droppingTime == null || calendarAppointment is! Appointment) {
      _clearDragSession(items: items);
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      _clearDragSession(items: items);
      return;
    }

    final item = items.where((entry) => entry.id == appointmentId).firstOrNull;
    if (item == null) {
      _clearDragSession(items: items);
      return;
    }

    final duration = item.endTime.difference(item.startTime);
    final newStart =
        session?.previewStart ?? AppointmentCalendarDisplay.snapTimeToSlot(droppingTime, slotMinutes: slotMinutes);
    final newEnd = newStart.add(duration);

    setState(() => _dragSession = null);

    _applySnappedPreview(
      items: items,
      appointmentId: item.id,
      newStart: newStart,
      newEnd: newEnd,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );

    if (AppointmentRescheduleValidation.isNoOpMove(appointment: item, newStart: newStart)) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    if (mode == AppointmentCalendarMode.doctors) {
      final resourceError = AppointmentRescheduleValidation.validateDoctorResourceMove(
        appointment: item,
        targetDoctorId: doctorIdFromCalendarResource(details.targetResource),
      );
      if (resourceError != null) {
        _revertCalendarItems(
          items,
          doctors: doctors,
          includeDoctorResources: includeDoctorResources,
          evenResourceRowColor: evenResourceRowColor,
          oddResourceRowColor: oddResourceRowColor,
        );
        if (mounted) {
          AppToast.error(context, message: resourceError);
        }
        return;
      }
    }

    final validationError = AppointmentRescheduleValidation.validateMove(
      appointment: item,
      newStart: newStart,
      schedule: schedule,
      branchAppointments: items,
    );
    if (validationError != null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: validationError);
      }
      return;
    }

    if (!mounted) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final confirmed = await AppointmentRescheduleConfirmDialog.show(
      context,
      appointment: item,
      newStart: newStart,
      newEnd: newEnd,
      schedule: schedule,
      branchAppointments: items,
    );
    if (confirmed == null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final finalStart = confirmed.start;
    final finalEnd = confirmed.end;

    if (AppointmentRescheduleValidation.isNoOpMove(appointment: item, newStart: finalStart) &&
        _isSameInstant(finalEnd, item.endTime)) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final postEditValidationError = AppointmentRescheduleValidation.validateMove(
      appointment: item,
      newStart: finalStart,
      newEnd: finalEnd,
      schedule: schedule,
      branchAppointments: items,
    );
    if (postEditValidationError != null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: postEditValidationError);
      }
      return;
    }

    _isProcessingDrag = true;
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .rescheduleAppointment(appointmentId: item.id, startTime: finalStart, endTime: finalEnd);
      if (!mounted) {
        return;
      }
      await ref.read(appointmentCalendarProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      AppToast.success(context, message: 'Appointment moved to ${_formatRange(finalStart, finalEnd)}.');
    } on RpcFailure catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: appointmentMessageForRpc(error));
      }
    } catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: 'Could not move the appointment. Please try again.');
      }
    } finally {
      _isProcessingDrag = false;
    }
  }

  void _onAppointmentResizeStart(
    AppointmentResizeStartDetails details, {
    required List<AppointmentListItem> items,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final calendarAppointment = details.appointment;
    if (calendarAppointment is! Appointment) {
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      return;
    }

    final item = items.where((entry) => entry.id == appointmentId).firstOrNull;
    if (item == null) {
      return;
    }

    final localStart = item.startTime.toLocal();
    final localEnd = item.endTime.toLocal();
    setState(() {
      _resizeSession = _CalendarResizeSession(
        item: item,
        previewStart: localStart,
        previewEnd: localEnd,
        slotMinutes: slotMinutes,
        baseItems: items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
    });
    _applyResizePreview(_resizeSession!);
  }

  void _onAppointmentResizeUpdate(
    AppointmentResizeUpdateDetails details, {
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final session = _resizeSession;
    final resizingTime = details.resizingTime;
    if (session == null || resizingTime == null) {
      return;
    }

    final snapped = AppointmentCalendarDisplay.snapTimeToSlot(resizingTime, slotMinutes: slotMinutes);
    final localStart = session.item.startTime.toLocal();
    final localEnd = session.item.endTime.toLocal();
    session.resizeFromStart ??=
        (snapped.difference(localStart).inMinutes).abs() <= (snapped.difference(localEnd).inMinutes).abs();

    if (session.resizeFromStart!) {
      session.previewStart = snapped;
      session.previewEnd = localEnd;
    } else {
      session.previewStart = localStart;
      session.previewEnd = snapped;
    }

    if (!session.previewEnd.isAfter(session.previewStart)) {
      return;
    }

    session
      ..doctors = doctors
      ..includeDoctorResources = includeDoctorResources
      ..evenResourceRowColor = evenResourceRowColor
      ..oddResourceRowColor = oddResourceRowColor;
    _applyResizePreview(session);
  }

  void _applyResizePreview(_CalendarResizeSession session) {
    final previewItems = [
      for (final entry in session.baseItems)
        if (entry.id == session.item.id)
          entry.copyWith(startTime: session.previewStart, endTime: session.previewEnd)
        else
          entry,
    ];
    _revertCalendarItems(
      previewItems,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
  }

  void _clearResizeSession({required List<AppointmentListItem> items}) {
    final session = _resizeSession;
    if (session == null) {
      return;
    }

    _revertCalendarItems(
      items,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
    setState(() => _resizeSession = null);
  }

  Future<void> _onAppointmentResizeEnd(
    AppointmentResizeEndDetails details, {
    required List<AppointmentListItem> items,
    required BranchWorkingSchedule schedule,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) async {
    if (_isProcessingDrag) {
      return;
    }

    final calendarAppointment = details.appointment;
    final startTime = details.startTime;
    final endTime = details.endTime;
    if (calendarAppointment is! Appointment || startTime == null || endTime == null) {
      _clearResizeSession(items: items);
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      _clearResizeSession(items: items);
      return;
    }

    final item = items.where((entry) => entry.id == appointmentId).firstOrNull;
    if (item == null) {
      _clearResizeSession(items: items);
      return;
    }

    final newStart = AppointmentCalendarDisplay.snapTimeToSlot(startTime, slotMinutes: slotMinutes);
    final newEnd = AppointmentCalendarDisplay.snapTimeToSlot(endTime, slotMinutes: slotMinutes);

    setState(() => _resizeSession = null);

    _applySnappedPreview(
      items: items,
      appointmentId: item.id,
      newStart: newStart,
      newEnd: newEnd,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );

    if (AppointmentRescheduleValidation.isNoOpResize(appointment: item, newStart: newStart, newEnd: newEnd)) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final validationError = AppointmentRescheduleValidation.validateMove(
      appointment: item,
      newStart: newStart,
      newEnd: newEnd,
      schedule: schedule,
      branchAppointments: items,
    );
    if (validationError != null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: validationError);
      }
      return;
    }

    if (!mounted) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final confirmed = await AppointmentRescheduleConfirmDialog.show(
      context,
      appointment: item,
      newStart: newStart,
      newEnd: newEnd,
      schedule: schedule,
      branchAppointments: items,
    );
    if (confirmed == null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final finalStart = confirmed.start;
    final finalEnd = confirmed.end;

    if (AppointmentRescheduleValidation.isNoOpResize(appointment: item, newStart: finalStart, newEnd: finalEnd)) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      return;
    }

    final postEditValidationError = AppointmentRescheduleValidation.validateMove(
      appointment: item,
      newStart: finalStart,
      newEnd: finalEnd,
      schedule: schedule,
      branchAppointments: items,
    );
    if (postEditValidationError != null) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: postEditValidationError);
      }
      return;
    }

    _isProcessingDrag = true;
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .rescheduleAppointment(appointmentId: item.id, startTime: finalStart, endTime: finalEnd);
      if (!mounted) {
        return;
      }
      await ref.read(appointmentCalendarProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      AppToast.success(context, message: 'Appointment updated to ${_formatRange(finalStart, finalEnd)}.');
    } on RpcFailure catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: appointmentMessageForRpc(error));
      }
    } catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        AppToast.error(context, message: 'Could not update the appointment. Please try again.');
      }
    } finally {
      _isProcessingDrag = false;
    }
  }

  void _revertCalendarItems(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    _dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
  }

  void _applySnappedPreview({
    required List<AppointmentListItem> items,
    required String appointmentId,
    required DateTime newStart,
    required DateTime newEnd,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final previewItems = [
      for (final entry in items)
        if (entry.id == appointmentId) entry.copyWith(startTime: newStart, endTime: newEnd) else entry,
    ];
    _revertCalendarItems(
      previewItems,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
  }

  static bool _supportsDragAndDrop(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => true,
      AppointmentCalendarMode.week => true,
      AppointmentCalendarMode.doctors => true,
      _ => false,
    };
  }

  void _onCalendarSelectionTap(CalendarTapDetails details, AppointmentCalendarMode mode) {
    if (details.targetElement == CalendarElement.appointment) {
      return;
    }

    if (mode == AppointmentCalendarMode.month) {
      final tappedDate = details.date;
      if (tappedDate != null &&
          (details.targetElement == CalendarElement.calendarCell || details.targetElement == CalendarElement.agenda)) {
        _calendarController.selectedDate = DateTime(tappedDate.year, tappedDate.month, tappedDate.day);
      }
      return;
    }

    _calendarController.selectedDate = null;
  }

  void _onCalendarTap(
    CalendarTapDetails details,
    List<AppointmentListItem> items, {
    required String? branchId,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool canCreate,
  }) {
    if (details.targetElement == CalendarElement.appointment) {
      final id = appointmentIdFromTap(details);
      _openAppointmentById(id, items);
      return;
    }

    if (!canCreate || branchId == null || branchId.isEmpty) {
      return;
    }

    if (mode != AppointmentCalendarMode.day && mode != AppointmentCalendarMode.week) {
      return;
    }

    if (details.targetElement != CalendarElement.calendarCell && details.targetElement != CalendarElement.agenda) {
      return;
    }

    final tappedDate = details.date;
    if (tappedDate == null) {
      return;
    }

    final slotRange = AppointmentCalendarDisplay.slotRangeFromTap(
      tappedDate: tappedDate,
      schedule: schedule,
      mode: mode,
      slotMinutes: slotMinutes,
    );

    unawaited(
      _showBookingSheet(
        branchId: branchId,
        schedule: schedule,
        slotStart: slotRange.start,
        slotEnd: slotRange.end,
        initialDoctorId:
            doctorIdFromCalendarResource(details.resource) ?? ref.read(appointmentCalendarProvider).selectedDoctorId,
        doctors: doctors,
      ),
    );
  }

  Future<void> _showBookingSheet({
    required String branchId,
    required BranchWorkingSchedule schedule,
    required DateTime slotStart,
    required DateTime slotEnd,
    String? initialDoctorId,
    required List<StaffListItem> doctors,
  }) async {
    final booked = await AppointmentBookingSheet.show(
      context,
      branchId: branchId,
      schedule: schedule,
      slotStart: slotStart,
      slotEnd: slotEnd,
      initialDoctorId: initialDoctorId,
      doctors: doctors,
    );
    if (booked == true && mounted) {
      await ref.read(appointmentCalendarProvider.notifier).refresh();
    }
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

  static bool _usesDoctorResources(AppointmentCalendarMode mode) {
    return mode == AppointmentCalendarMode.doctors;
  }

  static List<StaffListItem> _filteredDoctors(
    List<StaffListItem> doctors, {
    required String? selectedDoctorId,
    required AppointmentCalendarMode mode,
  }) {
    if (mode != AppointmentCalendarMode.doctors || selectedDoctorId == null || selectedDoctorId.isEmpty) {
      return doctors;
    }
    return doctors.where((doctor) => doctor.id == selectedDoctorId).toList(growable: false);
  }

  static CalendarView _calendarViewFor(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => CalendarView.day,
      AppointmentCalendarMode.week => CalendarView.week,
      AppointmentCalendarMode.month => CalendarView.month,
      AppointmentCalendarMode.schedule => CalendarView.schedule,
      AppointmentCalendarMode.doctors => CalendarView.timelineDay,
    };
  }

  static AppointmentCalendarMode _modeForCalendarView(CalendarView view) {
    return switch (view) {
      CalendarView.day => AppointmentCalendarMode.day,
      CalendarView.week => AppointmentCalendarMode.week,
      CalendarView.month => AppointmentCalendarMode.month,
      CalendarView.schedule => AppointmentCalendarMode.schedule,
      CalendarView.timelineDay => AppointmentCalendarMode.doctors,
      _ => AppointmentCalendarMode.week,
    };
  }

  static String _weekdayLabel(DateTime date) => DateFormat.EEEE().format(date);

  static bool _isSameInstant(DateTime a, DateTime b) {
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }

  static String _formatRange(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final day = DateFormat.yMMMd().format(localStart);
    final timeFormat = DateFormat('h:mm a');
    final from = timeFormat.format(localStart);
    final to = timeFormat.format(localEnd);
    return '$day · $from – $to';
  }
}

class _CalendarDragSession {
  _CalendarDragSession({
    required this.item,
    required this.previewStart,
    required this.slotMinutes,
    required this.baseItems,
    required this.doctors,
    required this.includeDoctorResources,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
  });

  final AppointmentListItem item;
  DateTime previewStart;
  final int slotMinutes;
  final List<AppointmentListItem> baseItems;
  List<StaffListItem> doctors;
  bool includeDoctorResources;
  Color evenResourceRowColor;
  Color oddResourceRowColor;
}

class _CalendarResizeSession {
  _CalendarResizeSession({
    required this.item,
    required this.previewStart,
    required this.previewEnd,
    required this.slotMinutes,
    required this.baseItems,
    required this.doctors,
    required this.includeDoctorResources,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
  });

  final AppointmentListItem item;
  DateTime previewStart;
  DateTime previewEnd;
  final int slotMinutes;
  final List<AppointmentListItem> baseItems;
  bool? resizeFromStart;
  List<StaffListItem> doctors;
  bool includeDoctorResources;
  Color evenResourceRowColor;
  Color oddResourceRowColor;
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
    final bounds = details.bounds;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: bounds.width,
        height: bounds.height,
        child: Container(
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
