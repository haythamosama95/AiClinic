import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_geometry.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_color_legend_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_filters.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_time_interval_button.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

/// Toolbar height below the appointments page header.
const appointmentCalendarToolbarHeight = 52.0;

/// Calendar toolbar with period navigation, view modes, filters, and booking.
class AppointmentCalendarToolbar extends ConsumerWidget {
  const AppointmentCalendarToolbar({
    required this.branchesAsync,
    required this.doctorsAsync,
    required this.appliedBranchId,
    required this.appliedDoctorId,
    required this.appliedStatuses,
    required this.hasActiveFilters,
    required this.onApplyFilters,
    required this.onClearFilters,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    super.key,
  });

  final AsyncValue<List<BranchListItem>> branchesAsync;
  final AsyncValue<List<StaffListItem>> doctorsAsync;
  final String? appliedBranchId;
  final String? appliedDoctorId;
  final Set<AppointmentStatus> appliedStatuses;
  final bool hasActiveFilters;
  final ValueChanged<AppointmentCalendarFilters> onApplyFilters;
  final VoidCallback onClearFilters;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  static const _modes = <AppointmentCalendarMode>[
    AppointmentCalendarMode.day,
    AppointmentCalendarMode.week,
    AppointmentCalendarMode.month,
    AppointmentCalendarMode.schedule,
    AppointmentCalendarMode.doctors,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final showNavigation = state.mode != AppointmentCalendarMode.schedule;
    final showTimeInterval = switch (state.mode) {
      AppointmentCalendarMode.day => true,
      AppointmentCalendarMode.week => true,
      AppointmentCalendarMode.doctors => true,
      _ => false,
    };
    final title = AppointmentCalendarGeometry.headerTitle(state.mode, state.focusDate);

    return AppToolbar(
      start: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNavigation) ...[
            AppIconButton(
              icon: const Icon(Icons.chevron_left),
              label: 'Previous period',
              onPressed: controller.previousPeriod,
            ),
            AppIconButton(
              icon: const Icon(Icons.chevron_right),
              label: 'Next period',
              onPressed: controller.nextPeriod,
            ),
            const SizedBox(width: AppSpacing.space2),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: showNavigation
                ? AppCalendarDateJumpPopover(
                    currentDate: state.focusDate,
                    onDateSelected: controller.setFocusDate,
                    triggerBuilder: (context, isOpen, onToggle) {
                      return AppCalendarDateJumpTitleTrigger(title: title, isOpen: isOpen, onToggle: onToggle);
                    },
                  )
                : Text(title, style: AppTypography.bodyStrong(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      end: Wrap(
        spacing: AppSpacing.space2,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (onToggleFullscreen != null)
            AppIconButton(
              icon: Icon(isFullscreen ? Icons.close_fullscreen : Icons.open_in_full),
              label: isFullscreen ? 'Exit fullscreen' : 'Expand calendar',
              onPressed: onToggleFullscreen,
            ),
          if (showTimeInterval) const AppointmentCalendarTimeIntervalButton(),
          const AppointmentCalendarColorLegendButton(),
          AppointmentCalendarFilterButton(
            branchesAsync: branchesAsync,
            doctorsAsync: doctorsAsync,
            appliedBranchId: appliedBranchId,
            appliedDoctorId: appliedDoctorId,
            appliedStatuses: appliedStatuses,
            showDoctorFilter: true,
            hasActiveFilters: hasActiveFilters,
            onApplyFilters: onApplyFilters,
            onClearFilters: onClearFilters,
          ),
          AppButton(
            size: AppButtonSize.sm,
            variant: AppButtonVariant.secondary,
            onPressed: controller.goToToday,
            child: const Text('Today'),
          ),
          AppSegmentedControl<String>(
            ariaLabel: 'Calendar view mode',
            size: AppSegmentedControlSize.sm,
            value: state.mode.name,
            onChanged: (value) {
              final mode = AppointmentCalendarMode.values.where((entry) => entry.name == value).firstOrNull;
              if (mode != null) {
                controller.setMode(mode);
              }
            },
            options: [
              for (final mode in _modes)
                SegmentedOption(
                  value: mode.name,
                  label: Text(_viewLabel(mode), style: AppTypography.caption(context)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _viewLabel(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => 'Day',
      AppointmentCalendarMode.week => 'Week',
      AppointmentCalendarMode.month => 'Month',
      AppointmentCalendarMode.schedule => 'Schedule',
      AppointmentCalendarMode.doctors => 'Doctors',
    };
  }
}
