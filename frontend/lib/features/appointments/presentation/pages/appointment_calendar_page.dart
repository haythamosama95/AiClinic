import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart' hide CalendarView;
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_fullscreen_overlay.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_tile.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_toolbar.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_view_header.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_page_shell.dart';
import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';

import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';

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
  int _statusFilterFingerprint = 0;
  int _themeFingerprint = -1;
  Brightness _syncedBrightness = Brightness.light;
  Set<String> _revealedAppointmentIds = {};
  int _revealGeneration = 0;
  int _lastRevealSourceFingerprint = -1;
  bool _isProcessingDrag = false;
  _CalendarDragSession? _dragSession;
  _CalendarResizeSession? _resizeSession;
  final GlobalKey _calendarHostKey = GlobalKey();
  OverlayEntry? _fullscreenOverlay;
  bool _isCalendarFullscreen = false;
  double? _calendarHostHeight;
  WidgetBuilder? _fullscreenCalendarBuilder;
  Future<void> Function()? _closeFullscreenOverlay;

  @override
  void initState() {
    super.initState();
    _dataSource = AppointmentCalendarDataSource(const []);
  }

  @override
  void dispose() {
    _fullscreenOverlay?.remove();
    _calendarController.dispose();
    super.dispose();
  }

  void _toggleCalendarFullscreen({required bool isFullscreen}) {
    if (isFullscreen) {
      unawaited(_closeFullscreenOverlay?.call());
    } else {
      _openCalendarFullscreen();
    }
  }

  void _openCalendarFullscreen() {
    if (_isCalendarFullscreen || _fullscreenCalendarBuilder == null) {
      return;
    }

    final hostContext = _calendarHostKey.currentContext;
    final sourceRect = hostContext == null ? null : globalRectOnScreen(hostContext);
    if (sourceRect == null) {
      return;
    }

    final box = hostContext!.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _calendarHostHeight = box.size.height;
    }

    _fullscreenOverlay = OverlayEntry(
      builder: (overlayContext) {
        return AppointmentCalendarFullscreenOverlay(
          sourceRect: sourceRect,
          onClose: _closeCalendarFullscreen,
          onReady: (close) => _closeFullscreenOverlay = close,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: _fullscreenCalendarBuilder!(overlayContext),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_fullscreenOverlay!);
    setState(() => _isCalendarFullscreen = true);
  }

  void _closeCalendarFullscreen() {
    _closeFullscreenOverlay = null;
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
    if (mounted) {
      setState(() => _isCalendarFullscreen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
    final schedule = AppointmentCalendarDisplay.resolveBranchSchedule(selectedBranch?.workingSchedule);
    final visibleItems = AppointmentCalendarDisplay.filterVisibleAppointments(
      state.items,
      schedule,
      selectedStatuses: state.selectedStatuses,
    );
    final allDoctors = doctorsAsync.maybeWhen(data: (items) => items, orElse: () => const <StaffListItem>[]);
    final doctors = _filteredDoctors(allDoctors, selectedDoctorId: state.selectedDoctorId, mode: state.mode);
    final hasActiveFilters = state.hasActiveFilters(initialBranchId: authState.context?.activeBranchId);
    final canCreate = ref.watch(permissionServiceProvider).canCreateAppointments();
    final oddResourceRowColor = colors.surfaceMuted.withValues(alpha: 0.3);
    _scheduleRevealIfNeeded(visibleItems, loading: state.loading);
    if (!state.loading) {
      if (_dragSession == null && _resizeSession == null) {
        _scheduleDataSourceSync(
          visibleItems,
          doctors: doctors,
          includeDoctorResources: _usesDoctorResources(state.mode),
          evenResourceRowColor: colors.surfaceCanvas,
          oddResourceRowColor: oddResourceRowColor,
          highlightedStatuses: state.selectedStatuses,
          brightness: Theme.of(context).brightness,
        );
      }
      _syncCalendarView(state);
    }

    final isClosedDay =
        (state.mode == AppointmentCalendarMode.day || state.mode == AppointmentCalendarMode.doctors) &&
        AppointmentCalendarDisplay.isClosedOnDate(schedule, state.focusDate);

    _fullscreenCalendarBuilder = (overlayContext) {
      final overlayHeight = MediaQuery.sizeOf(overlayContext).height - (AppSpacing.space4 * 2);
      return _buildCalendar(
        context: overlayContext,
        colors: overlayContext.appColors,
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
        viewportHeight: overlayHeight,
        hasActiveFilters: hasActiveFilters,
        isFullscreen: true,
      );
    };
    if (_isCalendarFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fullscreenOverlay?.markNeedsBuild());
    }

    return AppointmentPageShell(
      activeSection: AppointmentSection.calendar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!state.loading && state.error != null) ...[
            AppEmptyState(
              variant: AppEmptyStateVariant.error,
              title: 'Could not load calendar',
              description: state.error,
              action: EmptyStateAction(label: 'Retry', onPressed: controller.refresh),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
          if (!state.loading && state.error == null && isClosedDay)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: Text(
                'This branch is closed on ${_weekdayLabel(state.focusDate)}.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final calendar = _buildCalendar(
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
                  viewportHeight: constraints.maxHeight,
                  hasActiveFilters: hasActiveFilters,
                  isFullscreen: false,
                );

                if (_isCalendarFullscreen) {
                  return SizedBox(key: _calendarHostKey, height: _calendarHostHeight, child: const SizedBox.shrink());
                }

                return KeyedSubtree(key: _calendarHostKey, child: calendar);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar({
    required BuildContext context,
    required AppSemanticColors colors,
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
    required bool isFullscreen,
  }) {
    final slotLayout = AppointmentCalendarDisplay.timeSlotLayout(
      schedule: schedule,
      mode: state.mode,
      focusDate: state.focusDate,
      viewportHeight: (viewportHeight - appointmentCalendarToolbarHeight).clamp(240.0, viewportHeight),
      timeIntervalMinutes: state.timeIntervalMinutes,
    );
    final calendarSurface = colors.surfaceDefault;
    final allowDragAndDrop = canCreate && _supportsDragAndDrop(state.mode);
    final usesCustomViewHeader = AppointmentCalendarViewHeader.showsFor(state.mode);
    final syncfusionViewHeaderHeight = _syncfusionViewHeaderHeight(state.mode, usesCustomViewHeader);
    final viewHeaderTextStyle = AppTypography.bodyStrong(context).copyWith(
      color: colors.textPrimary,
      fontSize: 14,
      height: 18 / 14,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final calendarTheme = SfCalendarThemeData(
      backgroundColor: calendarSurface,
      headerBackgroundColor: calendarSurface,
      viewHeaderBackgroundColor: calendarSurface,
      agendaBackgroundColor: calendarSurface,
      allDayPanelColor: calendarSurface,
      cellBorderColor: colors.borderSubtle,
      headerTextStyle: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
      viewHeaderDayTextStyle: viewHeaderTextStyle,
      viewHeaderDateTextStyle: viewHeaderTextStyle,
      timeTextStyle: AppTypography.caption(context).copyWith(color: colors.textSecondary),
      todayHighlightColor: Colors.transparent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppointmentCalendarToolbar(
          branchesAsync: branchesAsync,
          doctorsAsync: doctorsAsync,
          appliedBranchId: state.selectedBranchId,
          appliedDoctorId: state.selectedDoctorId,
          appliedStatuses: state.selectedStatuses,
          hasActiveFilters: hasActiveFilters,
          onApplyFilters: (filters) => controller.applyFilters(
            branchId: filters.branchId,
            doctorId: filters.doctorId,
            statuses: filters.statuses,
          ),
          onClearFilters: controller.clearFilters,
          isFullscreen: isFullscreen,
          onToggleFullscreen: () => _toggleCalendarFullscreen(isFullscreen: isFullscreen),
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
        const SizedBox(height: AppSpacing.space4),
        Expanded(
          child: AppCard(
            variant: CardVariant.flat,
            padding: CardPadding.sm,
            child: SizedBox.expand(
              child: loading
                  ? const _CalendarSkeletonBody()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (usesCustomViewHeader)
                          AppointmentCalendarViewHeader(mode: state.mode, focusDate: state.focusDate, colors: colors),
                        Expanded(
                          child: SfCalendarTheme(
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
                              backgroundColor: calendarSurface,
                              cellBorderColor: colors.borderSubtle,
                              headerHeight: 0,
                              firstDayOfWeek: DateTime.monday,
                              viewHeaderHeight: syncfusionViewHeaderHeight,
                              todayHighlightColor: Colors.transparent,
                              todayTextStyle: viewHeaderTextStyle.copyWith(color: colors.actionPrimary),
                              resourceViewSettings: ResourceViewSettings(
                                showAvatar: false,
                                size: _timelineResourceRowHeight,
                                visibleResourceCount: -1,
                                displayNameTextStyle: AppTypography.bodySm(
                                  context,
                                ).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
                              ),
                              showNavigationArrow: false,
                              showTodayButton: false,
                              showDatePickerButton: false,
                              allowViewNavigation: false,
                              headerStyle: CalendarHeaderStyle(
                                backgroundColor: calendarSurface,
                                textStyle: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                              ),
                              viewHeaderStyle: ViewHeaderStyle(backgroundColor: calendarSurface),
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
                                timeIntervalWidth: slotLayout.timeIntervalWidth,
                                timelineAppointmentHeight: _timelineResourceRowHeight,
                                nonWorkingDays: slotLayout.nonWorkingDays,
                                timeFormat: 'HH:mm',
                                dateFormat: '',
                                dayFormat: 'd EEE',
                              ),
                              monthViewSettings: const MonthViewSettings(
                                showAgenda: true,
                                appointmentDisplayMode: MonthAppointmentDisplayMode.indicator,
                                agendaItemHeight: 56,
                              ),
                              scheduleViewSettings: const ScheduleViewSettings(appointmentItemHeight: 56),
                              specialRegions: [
                                for (final region in slotLayout.shadeRegions)
                                  TimeRegion(
                                    startTime: region.start,
                                    endTime: region.end,
                                    enablePointerInteraction: false,
                                    color: colors.surfaceMuted.withValues(alpha: 0.45),
                                  ),
                                if (state.mode == AppointmentCalendarMode.doctors)
                                  ...AppointmentCalendarDisplay.resourceRowStripeRegions(
                                    resourceIds: [
                                      for (final resource in _dataSource.resources ?? const <CalendarResource>[])
                                        resource.id,
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
                                      state.mode == AppointmentCalendarMode.doctors
                                          ? slotLayout.timeIntervalWidth
                                          : slotLayout.timeIntervalHeight,
                                      timelineAxisIsHorizontal: state.mode == AppointmentCalendarMode.doctors,
                                    )) {
                                  return const SizedBox.shrink();
                                }
                                final isRevealed = id == null || _revealedAppointmentIds.contains(id);
                                final item = id == null
                                    ? null
                                    : state.items.where((entry) => entry.id == id).firstOrNull;
                                final isDimmed =
                                    item != null &&
                                    !AppointmentCalendarDisplay.isStatusHighlighted(
                                      item.status,
                                      state.selectedStatuses,
                                    );
                                return Skeletonizer(
                                  enabled: !isRevealed,
                                  enableSwitchAnimation: true,
                                  effect: ShimmerEffect(
                                    baseColor: colors.surfaceMuted,
                                    highlightColor: colors.surfaceMuted.withValues(alpha: 0.55),
                                  ),
                                  containersColor: colors.surfaceMuted,
                                  child: AppointmentCalendarTile(
                                    details: details,
                                    item: item,
                                    mode: state.mode,
                                    isDimmed: isDimmed,
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
                                      evenResourceRowColor: colors.surfaceCanvas,
                                      oddResourceRowColor: oddResourceRowColor,
                                    )
                                  : null,
                              onDragUpdate: allowDragAndDrop
                                  ? (details) => _onAppointmentDragUpdate(
                                      details,
                                      slotMinutes: slotLayout.timeIntervalMinutes,
                                      doctors: doctors,
                                      includeDoctorResources: _usesDoctorResources(state.mode),
                                      evenResourceRowColor: colors.surfaceCanvas,
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
                                          evenResourceRowColor: colors.surfaceCanvas,
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
                                      evenResourceRowColor: colors.surfaceCanvas,
                                      oddResourceRowColor: oddResourceRowColor,
                                    )
                                  : null,
                              onAppointmentResizeUpdate: allowDragAndDrop
                                  ? (details) => _onAppointmentResizeUpdate(
                                      details,
                                      slotMinutes: slotLayout.timeIntervalMinutes,
                                      doctors: doctors,
                                      includeDoctorResources: _usesDoctorResources(state.mode),
                                      evenResourceRowColor: colors.surfaceCanvas,
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
                                          evenResourceRowColor: colors.surfaceCanvas,
                                          oddResourceRowColor: oddResourceRowColor,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
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

  void _scheduleDataSourceSync(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    required Set<AppointmentStatus> highlightedStatuses,
    required Brightness brightness,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragSession != null || _resizeSession != null) {
        return;
      }
      _syncDataSource(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
        highlightedStatuses: highlightedStatuses,
        brightness: brightness,
      );
    });
  }

  void _syncDataSource(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    required Set<AppointmentStatus> highlightedStatuses,
    required Brightness brightness,
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
    final statusFilterFingerprint = Object.hashAll(
      highlightedStatuses.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
    final themeFingerprint = brightness.index;
    if (itemsFingerprint == _itemsFingerprint &&
        resourceFingerprint == _resourceFingerprint &&
        statusFilterFingerprint == _statusFilterFingerprint &&
        themeFingerprint == _themeFingerprint) {
      return;
    }
    _itemsFingerprint = itemsFingerprint;
    _resourceFingerprint = resourceFingerprint;
    _statusFilterFingerprint = statusFilterFingerprint;
    _themeFingerprint = themeFingerprint;
    _syncedBrightness = brightness;
    _dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      highlightedStatuses: highlightedStatuses,
      brightness: brightness,
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
          appToast(context, AppToastInput(message: resourceError, variant: AppToastVariant.danger));
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
        appToast(context, AppToastInput(message: validationError, variant: AppToastVariant.danger));
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
        appToast(context, AppToastInput(message: postEditValidationError, variant: AppToastVariant.danger));
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
      appToast(
        context,
        AppToastInput(
          message: 'Appointment moved to ${_formatRange(finalStart, finalEnd)}.',
          variant: AppToastVariant.success,
        ),
      );
    } on RpcFailure catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        appToast(context, AppToastInput(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger));
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
        appToast(
          context,
          AppToastInput(message: 'Could not move the appointment. Please try again.', variant: AppToastVariant.danger),
        );
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
        appToast(context, AppToastInput(message: validationError, variant: AppToastVariant.danger));
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
        appToast(context, AppToastInput(message: postEditValidationError, variant: AppToastVariant.danger));
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
      appToast(
        context,
        AppToastInput(
          message: 'Appointment updated to ${_formatRange(finalStart, finalEnd)}.',
          variant: AppToastVariant.success,
        ),
      );
    } on RpcFailure catch (error) {
      _revertCalendarItems(
        items,
        doctors: doctors,
        includeDoctorResources: includeDoctorResources,
        evenResourceRowColor: evenResourceRowColor,
        oddResourceRowColor: oddResourceRowColor,
      );
      if (mounted) {
        appToast(context, AppToastInput(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger));
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
        appToast(
          context,
          AppToastInput(
            message: 'Could not update the appointment. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
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
    Brightness? brightness,
  }) {
    _dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      brightness: brightness ?? _syncedBrightness,
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
    context.nav.pushAppointmentDetail(item.id, preview: item);
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

  static double _syncfusionViewHeaderHeight(AppointmentCalendarMode mode, bool usesCustomViewHeader) {
    if (usesCustomViewHeader) {
      return 0;
    }

    return switch (mode) {
      AppointmentCalendarMode.month => 25,
      AppointmentCalendarMode.schedule => 0,
      _ => AppointmentCalendarDisplay.viewHeaderHeight,
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

class _CalendarPermissionDenied extends StatelessWidget {
  const _CalendarPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return const AppointmentPageShell(
      activeSection: AppointmentSection.calendar,
      child: AppEmptyState(variant: AppEmptyStateVariant.noAccess),
    );
  }
}

class _CalendarSkeletonBody extends StatelessWidget {
  const _CalendarSkeletonBody();

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonizerZone(
      child: SizedBox.expand(child: Bone(borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)))),
    );
  }
}
