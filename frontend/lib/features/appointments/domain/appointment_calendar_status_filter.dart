import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Calendar status visibility and filter rules.
abstract final class AppointmentCalendarStatusFilter {
  /// Cancelled and no-show appointments free their slot unless explicitly filtered in.
  static bool isHiddenOnCalendar(AppointmentStatus status) {
    return status == AppointmentStatus.cancelled || status == AppointmentStatus.noShow;
  }

  /// Whether [status] should render on the calendar for the current status filter.
  ///
  /// Inactive statuses stay hidden by default and only appear when selected in the
  /// status filter. Active workflow statuses are always eligible to render.
  static bool isVisibleOnCalendar(AppointmentStatus status, Set<AppointmentStatus> selectedStatuses) {
    if (!isHiddenOnCalendar(status)) {
      return true;
    }
    return selectedStatuses.contains(status);
  }

  /// Whether the calendar is using the default status filter (active workflow only).
  static bool isDefaultStatusFilter(Set<AppointmentStatus> selectedStatuses) => selectedStatuses.isEmpty;

  static Set<AppointmentStatus> get _calendarWorkflowStatuses => {
    for (final status in calendarStatusLegend)
      if (!isHiddenOnCalendar(status)) status,
  };

  static Set<AppointmentStatus> get _calendarHiddenStatuses => {
    for (final status in calendarStatusLegend)
      if (isHiddenOnCalendar(status)) status,
  };

  /// Whether a status chip should appear selected in the calendar filter panel.
  static bool isStatusChipSelected(AppointmentStatus status, Set<AppointmentStatus> selectedStatuses) {
    if (isHiddenOnCalendar(status)) {
      return selectedStatuses.contains(status);
    }

    final workflowInFilter = selectedStatuses.intersection(_calendarWorkflowStatuses);
    if (workflowInFilter.isEmpty) {
      return true;
    }
    return workflowInFilter.contains(status);
  }

  /// Updates [selectedStatuses] after toggling a status chip in the filter panel.
  static Set<AppointmentStatus> toggleStatusChip(AppointmentStatus status, Set<AppointmentStatus> selectedStatuses) {
    final workflow = _calendarWorkflowStatuses;
    final hidden = _calendarHiddenStatuses;
    final hiddenIncluded = selectedStatuses.intersection(hidden);
    final workflowInFilter = selectedStatuses.intersection(workflow);

    if (isHiddenOnCalendar(status)) {
      final nextHidden = Set<AppointmentStatus>.from(hiddenIncluded);
      if (nextHidden.contains(status)) {
        nextHidden.remove(status);
      } else {
        nextHidden.add(status);
      }
      if (workflowInFilter.isEmpty) {
        return nextHidden;
      }
      return {...workflowInFilter, ...nextHidden};
    }

    final chipSelected = isStatusChipSelected(status, selectedStatuses);
    if (chipSelected) {
      if (workflowInFilter.isEmpty) {
        final nextWorkflow = Set<AppointmentStatus>.from(workflow)..remove(status);
        return {...nextWorkflow, ...hiddenIncluded};
      }

      final nextWorkflow = Set<AppointmentStatus>.from(workflowInFilter)..remove(status);
      if (nextWorkflow.isEmpty || nextWorkflow.containsAll(workflow)) {
        return hiddenIncluded;
      }
      return {...nextWorkflow, ...hiddenIncluded};
    }

    final nextWorkflow = Set<AppointmentStatus>.from(workflowInFilter.isEmpty ? workflow : workflowInFilter)
      ..add(status);
    if (nextWorkflow.containsAll(workflow)) {
      return hiddenIncluded;
    }
    return {...nextWorkflow, ...hiddenIncluded};
  }

  static List<AppointmentListItem> filterVisibleAppointments(
    List<AppointmentListItem> items,
    BranchWorkingSchedule schedule, {
    Set<AppointmentStatus> selectedStatuses = const {},
  }) {
    return items
        .where(
          (item) =>
              isVisibleOnCalendar(item.status, selectedStatuses) &&
              AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: item.startTime, end: item.endTime),
        )
        .toList(growable: false);
  }

  /// Statuses shown in the calendar color legend and filter (excludes [AppointmentStatus.unknown]).
  static const List<AppointmentStatus> calendarStatusLegend = [
    AppointmentStatus.scheduled,
    AppointmentStatus.confirmed,
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
    AppointmentStatus.completed,
    AppointmentStatus.cancelled,
    AppointmentStatus.noShow,
  ];

  /// Branch hours used for slot layout and client-side visibility filtering.
  ///
  /// Falls back to [BranchWorkingSchedule.defaultSchedule] when the branch has no
  /// configured hours so appointments from the API are not hidden before setup.
  static BranchWorkingSchedule resolveBranchSchedule(BranchWorkingSchedule? schedule) {
    if (schedule == null || !schedule.hasConfiguredWorkingHours) {
      return BranchWorkingSchedule.defaultSchedule();
    }
    return schedule;
  }

  static bool isClosedOnDate(BranchWorkingSchedule schedule, DateTime date) {
    return !AppointmentBranchWorkingHours.isWorkingDay(schedule, date);
  }

  static bool showWeekends(BranchWorkingSchedule schedule) {
    return _isWorkingWeekday(schedule, BranchWeekday.saturday) || _isWorkingWeekday(schedule, BranchWeekday.sunday);
  }

  /// Whether [status] stays at full color for the current status filter.
  ///
  /// An empty [highlightedStatuses] means no status filter is active.
  static bool isStatusHighlighted(AppointmentStatus status, Set<AppointmentStatus> highlightedStatuses) {
    return highlightedStatuses.isEmpty || highlightedStatuses.contains(status);
  }

  static bool _isWorkingWeekday(BranchWorkingSchedule schedule, BranchWeekday weekday) {
    for (final day in schedule.days) {
      if (day.day == weekday) {
        return day.isWorkingDay;
      }
    }
    return false;
  }
}
