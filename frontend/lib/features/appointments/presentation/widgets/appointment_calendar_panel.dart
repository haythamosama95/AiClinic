import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_presentation_formatting.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Calendar panel with filters and [AppCalendar] bound to [appointmentCalendarProvider].
class AppointmentCalendarPanel extends ConsumerWidget {
  const AppointmentCalendarPanel({
    this.title = 'Calendar',
    this.description,
    this.onBookTap,
    this.showFilters = true,
    super.key,
  });

  final String title;
  final String? description;
  final VoidCallback? onBookTap;
  final bool showFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final doctorsAsync = ref.watch(appointmentCalendarDoctorsProvider);
    final branches = branchesAsync.maybeWhen(data: (items) => items, orElse: () => const <BranchListItem>[]);
    final doctors = doctorsAsync.maybeWhen(data: (items) => items, orElse: () => const <StaffListItem>[]);
    final selectedBranch = branches.where((item) => item.id == state.selectedBranchId).firstOrNull;
    final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
    final visibleItems = AppointmentCalendarDisplay.filterVisibleAppointments(
      state.items,
      schedule,
      selectedStatuses: state.selectedStatuses,
    );
    final slotLayout = AppointmentCalendarDisplay.timeSlotLayout(
      schedule: schedule,
      mode: state.mode,
      focusDate: state.focusDate,
    );
    final events = AppointmentPresentationFormatting.toCalendarEvents(
      context,
      visibleItems,
      highlightedStatuses: state.selectedStatuses,
    );
    final resources = state.mode == AppointmentCalendarMode.doctors
        ? AppointmentPresentationFormatting.toCalendarResources([
            for (final doctor in doctors) (id: doctor.id, name: doctor.fullName),
          ])
        : null;

    final contentState = switch (true) {
      _ when state.loading && state.items.isEmpty => AppContentState.loading,
      _ when state.error != null && state.items.isEmpty => AppContentState.error,
      _ when !state.loading && visibleItems.isEmpty => AppContentState.emptyFirstRun,
      _ => AppContentState.ready,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFilters)
          _CalendarToolbar(
            state: state,
            controller: controller,
            branches: branches,
            doctors: doctors,
            onBookTap: onBookTap,
          ),
        if (showFilters) const SizedBox(height: AppSpacing.s4),
        AppSectionHeader(
          title: title,
          description: description ?? AppointmentCalendarDisplay.headerTitle(state.mode, state.focusDate),
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: LucideIcons.chevronLeft,
                semanticLabel: 'Previous period',
                onPressed: controller.previousPeriod,
              ),
              AppButton(
                label: 'Today',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: controller.goToToday,
              ),
              AppIconButton(
                icon: LucideIcons.chevronRight,
                semanticLabel: 'Next period',
                onPressed: controller.nextPeriod,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Expanded(
          child: AppAsyncStateView(
            state: contentState,
            config: AppContentStateConfig(
              errorMessage: state.error,
              onRetry: controller.refresh,
              emptyFirstRunTitle: 'No appointments',
              emptyFirstRunDescription: 'Book an appointment or adjust filters to see more slots.',
              emptyFirstRunActionLabel: onBookTap == null ? null : 'Book appointment',
              onEmptyFirstRunAction: onBookTap,
            ),
            child: AppCalendar(
              events: events,
              view: AppointmentPresentationFormatting.calendarViewFor(state.mode),
              selectedDate: state.focusDate,
              onDateChanged: controller.setFocusDate,
              onViewChanged: (view) => controller.setMode(AppointmentPresentationFormatting.calendarModeFor(view)),
              onEventTap: (event) => _onEventTap(context, event.id, visibleItems),
              onCreate: onBookTap == null
                  ? null
                  : (_) => onBookTap!(),
              resources: resources,
              startHour: slotLayout.startHour.floor(),
              endHour: slotLayout.endHour.ceil(),
            ),
          ),
        ),
      ],
    );
  }

  void _onEventTap(BuildContext context, String eventId, List<AppointmentListItem> items) {
    final item = items.where((entry) => entry.id == eventId).firstOrNull;
    if (item == null) {
      return;
    }
    context.nav.pushAppointmentDetail(item.id, preview: item);
  }
}

class _CalendarToolbar extends ConsumerWidget {
  const _CalendarToolbar({
    required this.state,
    required this.controller,
    required this.branches,
    required this.doctors,
    this.onBookTap,
  });

  final AppointmentCalendarState state;
  final AppointmentCalendarController controller;
  final List<BranchListItem> branches;
  final List<StaffListItem> doctors;
  final VoidCallback? onBookTap;

  static const _modeOptions = [
    AppSegmentedOption(value: AppointmentCalendarMode.day, label: 'Day'),
    AppSegmentedOption(value: AppointmentCalendarMode.week, label: 'Week'),
    AppSegmentedOption(value: AppointmentCalendarMode.month, label: 'Month'),
    AppSegmentedOption(value: AppointmentCalendarMode.schedule, label: 'Agenda'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authBranchId = ref.watch(authSessionProvider).context?.activeBranchId;
    final hasActiveFilters = state.hasActiveFilters(initialBranchId: authBranchId);

    return AppToolbar(
      start: AppSegmentedControl<AppointmentCalendarMode>(
        options: _modeOptions,
        value: state.mode,
        onChanged: controller.setMode,
        semanticLabel: 'Calendar mode',
        size: AppSegmentedControlSize.sm,
      ),
      end: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (branches.isNotEmpty)
            SizedBox(
              width: 180,
              child: AppSelect<String?>(
                options: [
                  for (final branch in branches)
                    AppSelectOption(value: branch.id, label: branch.name),
                ],
                value: state.selectedBranchId,
                placeholder: 'Branch',
                onChanged: (branchId) => controller.setBranchFilter(branchId),
              ),
            ),
          if (doctors.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.s2),
            SizedBox(
              width: 180,
              child: AppSelect<String?>(
                options: [
                  const AppSelectOption<String?>(value: null, label: 'All doctors'),
                  for (final doctor in doctors)
                    AppSelectOption(value: doctor.id, label: doctor.fullName),
                ],
                value: state.selectedDoctorId,
                placeholder: 'Doctor',
                onChanged: controller.setDoctorFilter,
              ),
            ),
          ],
          if (hasActiveFilters) ...[
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: 'Clear filters',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: controller.clearFilters,
            ),
          ],
          if (onBookTap != null) ...[
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: 'Book',
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.plus,
              onPressed: onBookTap,
            ),
          ],
        ],
      ),
    );
  }
}
