import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart' hide CalendarView;
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_layout.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_status_filter.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_fullscreen_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_reschedule_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_reveal_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_sync_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_action.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_geometry.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_skeleton_body.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_tile.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_tile_context_menu.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_toolbar.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_view_header.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_page_shell.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

/// Resource row height in the doctor timeline view; must match [TimeSlotViewSettings.timelineAppointmentHeight].
const appointmentCalendarTimelineResourceRowHeight = 120.0;

/// Syncfusion calendar surface with toolbar, tiles, and gesture handlers.
class AppointmentCalendarView extends StatelessWidget {
  const AppointmentCalendarView({
    required this.calendarController,
    required this.dataSource,
    required this.revealedAppointmentIds,
    required this.draggedAppointmentId,
    required this.resizedAppointmentId,
    required this.itemById,
    required this.colors,
    required this.state,
    required this.controller,
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.schedule,
    required this.doctors,
    required this.canCreate,
    required this.canCancel,
    required this.visibleItems,
    required this.oddResourceRowColor,
    required this.loading,
    required this.viewportHeight,
    required this.hasActiveFilters,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onViewChanged,
    required this.onAppointmentTileTap,
    required this.onEditAppointment,
    required this.onCancelAppointment,
    required this.onCalendarSelectionTap,
    required this.onCalendarTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    super.key,
  });

  final CalendarController calendarController;
  final AppointmentCalendarDataSource dataSource;
  final Set<String> revealedAppointmentIds;
  final String? draggedAppointmentId;
  final String? resizedAppointmentId;
  final AppointmentListItem? Function(String? id) itemById;
  final AppSemanticColors colors;
  final AppointmentCalendarState state;
  final AppointmentCalendarController controller;
  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final BranchWorkingSchedule schedule;
  final List<StaffListItem> doctors;
  final bool canCreate;
  final bool canCancel;
  final List<AppointmentListItem> visibleItems;
  final Color oddResourceRowColor;
  final bool loading;
  final double viewportHeight;
  final bool hasActiveFilters;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final void Function(ViewChangedDetails details) onViewChanged;
  final void Function(CalendarAppointmentDetails details) onAppointmentTileTap;
  final void Function(AppointmentListItem item) onEditAppointment;
  final void Function(AppointmentListItem item) onCancelAppointment;
  final void Function(CalendarTapDetails details) onCalendarSelectionTap;
  final void Function(CalendarTapDetails details) onCalendarTap;
  final void Function(AppointmentDragStartDetails details)? onDragStart;
  final void Function(AppointmentDragUpdateDetails details)? onDragUpdate;
  final void Function(AppointmentDragEndDetails details)? onDragEnd;
  final void Function(AppointmentResizeStartDetails details)? onResizeStart;
  final void Function(AppointmentResizeUpdateDetails details)? onResizeUpdate;
  final void Function(AppointmentResizeEndDetails details)? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final slotLayout = AppointmentCalendarGeometry.timeSlotLayout(
      schedule: schedule,
      mode: state.mode,
      focusDate: state.focusDate,
      viewportHeight: (viewportHeight - appointmentCalendarToolbarHeight).clamp(240.0, viewportHeight),
      timeIntervalMinutes: state.timeIntervalMinutes,
    );
    final calendarSurface = colors.surfaceDefault;
    final allowDragAndDrop = canCreate && supportsCalendarViewDragAndDrop(state.mode);
    final usesCustomViewHeader = AppointmentCalendarViewHeader.showsFor(state.mode);
    final syncfusionViewHeaderHeight = AppointmentCalendarSyncController.syncfusionViewHeaderHeight(
      state.mode,
      usesCustomViewHeader,
    );
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
          onToggleFullscreen: onToggleFullscreen,
        ),
        const SizedBox(height: AppSpacing.space4),
        Expanded(
          child: AppCard(
            variant: CardVariant.flat,
            padding: CardPadding.sm,
            child: SizedBox.expand(
              child: loading
                  ? const AppointmentCalendarSkeletonBody()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (usesCustomViewHeader)
                          AppointmentCalendarViewHeader(mode: state.mode, focusDate: state.focusDate, colors: colors),
                        Expanded(
                          child: SfCalendarTheme(
                            data: calendarTheme,
                            child: SfCalendar(
                              controller: calendarController,
                              view: AppointmentCalendarSyncController.calendarViewFor(state.mode),
                              allowedViews: const [
                                CalendarView.day,
                                CalendarView.week,
                                CalendarView.month,
                                CalendarView.schedule,
                                CalendarView.timelineDay,
                              ],
                              dataSource: dataSource,
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
                                size: appointmentCalendarTimelineResourceRowHeight,
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
                                  ? AppointmentCalendarLayout.closedDatesInMonth(schedule, state.focusDate)
                                  : const [],
                              timeSlotViewSettings: TimeSlotViewSettings(
                                startHour: slotLayout.startHour,
                                endHour: slotLayout.endHour,
                                timeInterval: Duration(minutes: slotLayout.timeIntervalMinutes),
                                timeIntervalHeight: slotLayout.timeIntervalHeight,
                                timeIntervalWidth: slotLayout.timeIntervalWidth,
                                timelineAppointmentHeight: appointmentCalendarTimelineResourceRowHeight,
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
                                  ...AppointmentCalendarGeometry.resourceRowStripeRegions(
                                    resourceIds: [
                                      for (final resource in dataSource.resources ?? const <CalendarResource>[])
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
                                    (draggedAppointmentId == id || resizedAppointmentId == id) &&
                                    !AppointmentCalendarGeometry.isAlignedToSlotGrid(
                                      details.bounds,
                                      state.mode == AppointmentCalendarMode.doctors
                                          ? slotLayout.timeIntervalWidth
                                          : slotLayout.timeIntervalHeight,
                                      timelineAxisIsHorizontal: state.mode == AppointmentCalendarMode.doctors,
                                    )) {
                                  return const SizedBox.shrink();
                                }
                                final isRevealed = id == null || revealedAppointmentIds.contains(id);
                                final item = itemById(id);
                                final isDimmed =
                                    item != null &&
                                    !AppointmentCalendarStatusFilter.isStatusHighlighted(
                                      item.status,
                                      state.selectedStatuses,
                                    );
                                final menuEntries = item != null && isRevealed
                                    ? appointmentCalendarTileMenuEntries(
                                        item: item,
                                        canEdit: canCreate,
                                        canCancel: canCancel,
                                        onEdit: () => onEditAppointment(item),
                                        onCancel: () => onCancelAppointment(item),
                                      )
                                    : null;
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
                                    onTap: isRevealed ? () => onAppointmentTileTap(details) : () {},
                                    contextMenuEntries: menuEntries,
                                  ),
                                );
                              },
                              onViewChanged: (details) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  onViewChanged(details);
                                });
                              },
                              allowDragAndDrop: allowDragAndDrop,
                              allowAppointmentResize: allowDragAndDrop,
                              dragAndDropSettings: const DragAndDropSettings(showTimeIndicator: false),
                              onDragStart: onDragStart,
                              onDragUpdate: onDragUpdate,
                              onDragEnd: onDragEnd == null ? null : onDragEnd,
                              onTap: (details) {
                                onCalendarSelectionTap(details);
                                onCalendarTap(details);
                              },
                              onAppointmentResizeStart: onResizeStart,
                              onAppointmentResizeUpdate: onResizeUpdate,
                              onAppointmentResizeEnd: onResizeEnd == null ? null : onResizeEnd,
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
}

bool supportsCalendarViewDragAndDrop(AppointmentCalendarMode mode) {
  return switch (mode) {
    AppointmentCalendarMode.day => true,
    AppointmentCalendarMode.week => true,
    AppointmentCalendarMode.doctors => true,
    _ => false,
  };
}

/// Calendar body with provider listeners, gesture wiring, and booking actions.
class AppointmentCalendarPageHost extends ConsumerStatefulWidget {
  const AppointmentCalendarPageHost({
    required this.sync,
    required this.reveal,
    required this.fullscreen,
    required this.reschedule,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
    required this.brightness,
    required this.onChanged,
    super.key,
  });

  final AppointmentCalendarSyncController sync;
  final AppointmentCalendarRevealController reveal;
  final AppointmentCalendarFullscreenController fullscreen;
  final AppointmentCalendarRescheduleController reschedule;
  final Color evenResourceRowColor;
  final Color oddResourceRowColor;
  final Brightness brightness;
  final VoidCallback onChanged;

  @override
  ConsumerState<AppointmentCalendarPageHost> createState() => AppointmentCalendarPageHostState();
}

class AppointmentCalendarPageHostState extends ConsumerState<AppointmentCalendarPageHost> {
  AppointmentCalendarSyncController get _sync => widget.sync;
  AppointmentCalendarRevealController get _reveal => widget.reveal;
  AppointmentCalendarFullscreenController get _fullscreen => widget.fullscreen;
  AppointmentCalendarRescheduleController get _reschedule => widget.reschedule;

  void syncFromCurrentState() {
    final state = ref.read(appointmentCalendarProvider);
    final visibleItems = _visibleItemsFor(state);
    final doctors = _doctorsFor(state);

    _sync.onStateChanged(
      next: state,
      visibleItems: visibleItems,
      doctors: doctors,
      includeDoctorResources: usesDoctorCalendarResources(state.mode),
      evenResourceRowColor: widget.evenResourceRowColor,
      oddResourceRowColor: widget.oddResourceRowColor,
      highlightedStatuses: state.selectedStatuses,
      brightness: widget.brightness,
      hasActiveGesture: _reschedule.hasActiveGesture,
    );
    _reveal.scheduleRevealIfNeeded(visibleItems, loading: state.loading, onChanged: widget.onChanged);
  }

  List<AppointmentListItem> _visibleItemsFor(AppointmentCalendarState state) {
    return AppointmentCalendarStatusFilter.filterVisibleAppointments(
      state.items,
      _scheduleFor(state),
      selectedStatuses: state.selectedStatuses,
    );
  }

  BranchWorkingSchedule _scheduleFor(AppointmentCalendarState state) {
    final branches = ref.read(appointmentCalendarBranchesProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <BranchListItem>[],
        );
    final selectedBranch = branches.where((item) => item.id == state.selectedBranchId).firstOrNull;
    return AppointmentCalendarStatusFilter.resolveBranchSchedule(selectedBranch?.workingSchedule);
  }

  List<StaffListItem> _doctorsFor(AppointmentCalendarState state) {
    final allDoctors = ref.read(appointmentCalendarDoctorsProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <StaffListItem>[],
        );
    return filteredCalendarDoctors(allDoctors, selectedDoctorId: state.selectedDoctorId, mode: state.mode);
  }

  void _onGestureComplete() {
    final state = ref.read(appointmentCalendarProvider);
    _sync.applyPendingSync(
      doctors: _doctorsFor(state),
      includeDoctorResources: usesDoctorCalendarResources(state.mode),
      evenResourceRowColor: widget.evenResourceRowColor,
      oddResourceRowColor: widget.oddResourceRowColor,
      highlightedStatuses: state.selectedStatuses,
      brightness: widget.brightness,
    );
  }

  Widget _buildCalendarView({
    required BuildContext context,
    required AppointmentCalendarState state,
    required AppointmentCalendarController controller,
    required AsyncValue<List<BranchListItem>> branchesAsync,
    required AsyncValue<List<StaffListItem>> doctorsAsync,
    required BranchWorkingSchedule schedule,
    required List<StaffListItem> doctors,
    required bool canCreate,
    required bool canCancel,
    required List<AppointmentListItem> visibleItems,
    required bool loading,
    required double viewportHeight,
    required bool hasActiveFilters,
    required bool isFullscreen,
  }) {
    final syncContext = AppointmentRescheduleSyncContext(
      doctors: doctors,
      includeDoctorResources: usesDoctorCalendarResources(state.mode),
      evenResourceRowColor: widget.evenResourceRowColor,
      oddResourceRowColor: widget.oddResourceRowColor,
    );
    final allowGestures = canCreate && supportsCalendarViewDragAndDrop(state.mode);

    return AppointmentCalendarView(
      calendarController: _sync.calendarController,
      dataSource: _sync.dataSource,
      revealedAppointmentIds: _reveal.revealedAppointmentIds,
      draggedAppointmentId: _reschedule.dragSession?.item.id,
      resizedAppointmentId: _reschedule.resizeSession?.item.id,
      itemById: _sync.itemById,
      colors: context.appColors,
      state: state,
      controller: controller,
      branchesAsync: branchesAsync,
      doctorsAsync: doctorsAsync,
      schedule: schedule,
      doctors: doctors,
      canCreate: canCreate,
      canCancel: canCancel,
      visibleItems: visibleItems,
      oddResourceRowColor: widget.oddResourceRowColor,
      loading: loading,
      viewportHeight: viewportHeight,
      hasActiveFilters: hasActiveFilters,
      isFullscreen: isFullscreen,
      onToggleFullscreen: () {
        _fullscreen.toggle(
          context: context,
          isCurrentlyFullscreen: isFullscreen,
          calendarBuilder: (overlayContext) => _buildCalendarView(
            context: overlayContext,
            state: ref.read(appointmentCalendarProvider),
            controller: ref.read(appointmentCalendarProvider.notifier),
            branchesAsync: ref.read(appointmentCalendarBranchesProvider),
            doctorsAsync: ref.read(appointmentCalendarDoctorsProvider),
            schedule: _scheduleFor(ref.read(appointmentCalendarProvider)),
            doctors: _doctorsFor(ref.read(appointmentCalendarProvider)),
            canCreate: AuthRouteGuard.canAccessAppointmentBooking(ref.read(authSessionProvider)),
            canCancel: AuthRouteGuard.canAccessAppointmentCancelActions(ref.read(authSessionProvider)),
            visibleItems: _visibleItemsFor(ref.read(appointmentCalendarProvider)),
            loading: ref.read(appointmentCalendarProvider).loading,
            viewportHeight: MediaQuery.sizeOf(overlayContext).height - (AppSpacing.space4 * 2),
            hasActiveFilters: ref.read(appointmentCalendarProvider).hasActiveFilters(
                  initialBranchId: ref.read(authSessionProvider).context?.activeBranchId,
                ),
            isFullscreen: true,
          ),
        );
        widget.onChanged();
      },
      onViewChanged: (details) {
        unawaited(_sync.onViewChanged(details, controller: controller, state: state));
      },
      onAppointmentTileTap: (details) => _openAppointmentById(appointmentIdFromAppointmentDetails(details)),
      onEditAppointment: (item) => _editAppointment(
        item,
        branchId: state.selectedBranchId,
        schedule: schedule,
        doctors: doctors,
        branchName: branchesAsync.maybeWhen(
          data: (branches) => branches.where((entry) => entry.id == state.selectedBranchId).firstOrNull?.name,
          orElse: () => null,
        ),
      ),
      onCancelAppointment: _cancelAppointment,
      onCalendarSelectionTap: (details) => _onCalendarSelectionTap(details, state.mode),
      onCalendarTap: (details) => _onCalendarTap(
        details,
        branchId: state.selectedBranchId,
        schedule: schedule,
        mode: state.mode,
        slotMinutes: state.timeIntervalMinutes,
        doctors: doctors,
        canCreate: canCreate,
      ),
      onDragStart: allowGestures
          ? (details) => _reschedule.onDragStart(
                details,
                items: visibleItems,
                slotMinutes: state.timeIntervalMinutes,
                doctors: doctors,
                includeDoctorResources: usesDoctorCalendarResources(state.mode),
                evenResourceRowColor: widget.evenResourceRowColor,
                oddResourceRowColor: widget.oddResourceRowColor,
              )
          : null,
      onDragUpdate: allowGestures
          ? (details) => _reschedule.onDragUpdate(
                details,
                slotMinutes: state.timeIntervalMinutes,
                doctors: doctors,
                includeDoctorResources: usesDoctorCalendarResources(state.mode),
                evenResourceRowColor: widget.evenResourceRowColor,
                oddResourceRowColor: widget.oddResourceRowColor,
              )
          : null,
      onDragEnd: allowGestures
          ? (details) {
              unawaited(
                _reschedule.onDragEnd(
                  details,
                  context: context,
                  ref: ref,
                  items: visibleItems,
                  schedule: schedule,
                  mode: state.mode,
                  slotMinutes: state.timeIntervalMinutes,
                  syncContext: syncContext,
                  onGestureComplete: _onGestureComplete,
                ),
              );
            }
          : null,
      onResizeStart: allowGestures
          ? (details) => _reschedule.onResizeStart(
                details,
                items: visibleItems,
                slotMinutes: state.timeIntervalMinutes,
                doctors: doctors,
                includeDoctorResources: usesDoctorCalendarResources(state.mode),
                evenResourceRowColor: widget.evenResourceRowColor,
                oddResourceRowColor: widget.oddResourceRowColor,
              )
          : null,
      onResizeUpdate: allowGestures
          ? (details) => _reschedule.onResizeUpdate(
                details,
                slotMinutes: state.timeIntervalMinutes,
                doctors: doctors,
                includeDoctorResources: usesDoctorCalendarResources(state.mode),
                evenResourceRowColor: widget.evenResourceRowColor,
                oddResourceRowColor: widget.oddResourceRowColor,
              )
          : null,
      onResizeEnd: allowGestures
          ? (details) {
              unawaited(
                _reschedule.onResizeEnd(
                  details,
                  context: context,
                  ref: ref,
                  items: visibleItems,
                  schedule: schedule,
                  mode: state.mode,
                  slotMinutes: state.timeIntervalMinutes,
                  syncContext: syncContext,
                  onGestureComplete: _onGestureComplete,
                ),
              );
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appointmentCalendarProvider, (previous, next) {
      syncFromCurrentState();
      if (previous != next && _fullscreen.isOpen) {
        _fullscreen.refreshOverlay();
      }
    });
    ref.listen(appointmentCalendarBranchesProvider, (_, __) => syncFromCurrentState());
    ref.listen(appointmentCalendarDoctorsProvider, (_, __) => syncFromCurrentState());

    final auth = ref.watch(authSessionProvider);
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final doctorsAsync = ref.watch(appointmentCalendarDoctorsProvider);
    final schedule = _scheduleFor(state);
    final visibleItems = _visibleItemsFor(state);
    final doctors = _doctorsFor(state);
    final hasActiveFilters = state.hasActiveFilters(initialBranchId: auth.context?.activeBranchId);
    final canCreate = AuthRouteGuard.canAccessAppointmentBooking(auth);
    final canCancel = AuthRouteGuard.canAccessAppointmentCancelActions(auth);
    final colors = context.appColors;

    final isClosedDay =
        (state.mode == AppointmentCalendarMode.day || state.mode == AppointmentCalendarMode.doctors) &&
        AppointmentCalendarStatusFilter.isClosedOnDate(schedule, state.focusDate);

    final onBookAppointment = _bookAppointmentAction(
      canCreate: canCreate,
      state: state,
      schedule: schedule,
      doctors: doctors,
    );

    return AppointmentPageShell(
      actions: onBookAppointment == null
          ? null
          : AppButton(size: AppButtonSize.md, onPressed: onBookAppointment, child: const Text('Book appointment')),
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
                'This branch is closed on ${DateFormat.EEEE().format(state.focusDate)}.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final calendar = _buildCalendarView(
                  context: context,
                  state: state,
                  controller: controller,
                  branchesAsync: branchesAsync,
                  doctorsAsync: doctorsAsync,
                  schedule: schedule,
                  doctors: doctors,
                  canCreate: canCreate,
                  canCancel: canCancel,
                  visibleItems: visibleItems,
                  loading: state.loading,
                  viewportHeight: constraints.maxHeight,
                  hasActiveFilters: hasActiveFilters,
                  isFullscreen: false,
                );

                if (_fullscreen.isOpen) {
                  return SizedBox(
                    key: _fullscreen.calendarHostKey,
                    height: _fullscreen.calendarHostHeight,
                    child: const SizedBox.shrink(),
                  );
                }

                return KeyedSubtree(key: _fullscreen.calendarHostKey, child: calendar);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onCalendarSelectionTap(CalendarTapDetails details, AppointmentCalendarMode mode) {
    if (details.targetElement == CalendarElement.appointment) {
      return;
    }

    if (mode == AppointmentCalendarMode.month) {
      final tappedDate = details.date;
      if (tappedDate != null &&
          (details.targetElement == CalendarElement.calendarCell || details.targetElement == CalendarElement.agenda)) {
        _sync.calendarController.selectedDate = DateTime(tappedDate.year, tappedDate.month, tappedDate.day);
      }
      return;
    }

    _sync.calendarController.selectedDate = null;
  }

  void _onCalendarTap(
    CalendarTapDetails details, {
    required String? branchId,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool canCreate,
  }) {
    if (details.targetElement == CalendarElement.appointment) {
      _openAppointmentById(appointmentIdFromTap(details));
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

    final slotRange = AppointmentCalendarLayout.slotRangeFromTap(
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

  VoidCallback? _bookAppointmentAction({
    required bool canCreate,
    required AppointmentCalendarState state,
    required BranchWorkingSchedule schedule,
    required List<StaffListItem> doctors,
  }) {
    if (!canCreate || state.selectedBranchId == null || state.selectedBranchId!.isEmpty) {
      return null;
    }

    return () {
      final slotRange = AppointmentCalendarLayout.slotRangeFromTap(
        tappedDate: state.focusDate,
        schedule: schedule,
        mode: state.mode,
        slotMinutes: state.timeIntervalMinutes,
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
    };
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
      branchName: ref
          .read(appointmentCalendarBranchesProvider)
          .maybeWhen(
            data: (branches) => branches.where((item) => item.id == branchId).firstOrNull?.name,
            orElse: () => null,
          ),
    );
    if (booked == true && mounted) {
      await ref.read(appointmentCalendarProvider.notifier).refresh();
    }
  }

  void _openAppointmentById(String? id) {
    if (id == null) {
      return;
    }
    final item = _sync.itemById(id);
    if (item == null) {
      return;
    }
    context.nav.pushAppointmentDetail(item.id, preview: item);
  }

  Future<void> _editAppointment(
    AppointmentListItem item, {
    required String? branchId,
    required BranchWorkingSchedule schedule,
    required List<StaffListItem> doctors,
    String? branchName,
  }) async {
    if (branchId == null || branchId.isEmpty) {
      return;
    }

    try {
      final detail = await ref.read(appointmentRepositoryProvider).getAppointment(appointmentId: item.id);
      if (!mounted) {
        return;
      }

      final updated = await AppointmentBookingSheet.show(
        context,
        branchId: branchId,
        schedule: schedule,
        slotStart: detail.startTime.toLocal(),
        slotEnd: detail.endTime.toLocal(),
        initialDoctorId: detail.doctorId,
        doctors: doctors,
        existingAppointment: detail,
        branchName: branchName,
      );
      if (updated == true && mounted) {
        await ref.read(appointmentCalendarProvider.notifier).refresh();
      }
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(context, AppToastInput(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger));
      }
    } catch (error, stack) {
      AppLog.warning('appointments.calendar.edit_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.calendar.edit_failed.stack $stack');
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not open the appointment for editing. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    }
  }

  Future<void> _cancelAppointment(AppointmentListItem item) async {
    final cancelled = await runAppointmentCancelFlow(context, ref, item);
    if (!cancelled || !mounted) {
      return;
    }
    await ref.read(appointmentCalendarProvider.notifier).refresh();
  }
}
