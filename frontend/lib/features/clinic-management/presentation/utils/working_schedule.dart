import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';

BranchWorkingSchedule defaultWorkingSchedule() => BranchWorkingSchedule.defaultSchedule();

BranchWorkingSchedule emptyWorkingSchedule() => BranchWorkingSchedule.emptySchedule();

bool hasConfiguredWorkingHours(BranchWorkingSchedule schedule) => schedule.hasConfiguredWorkingHours;

String weekdayLabel(BranchWeekday day) => day.label;

String formatWorkingHoursSummary(BranchWorkingSchedule? schedule) {
  if (schedule == null) {
    return 'Not configured';
  }

  final openDays = schedule.days.where((day) => day.isWorkingDay && day.openTime != null && day.closeTime != null);
  final openList = openDays.toList(growable: false);
  if (openList.isEmpty) {
    return 'Not configured';
  }
  if (openList.length == 1) {
    final day = openList.first;
    return '${weekdayLabel(day.day)} ${day.openTime}–${day.closeTime}';
  }

  final first = openList.first;
  final sameHours = openList.every((day) => day.openTime == first.openTime && day.closeTime == first.closeTime);
  if (sameHours) {
    return '${openList.length} days · ${first.openTime}–${first.closeTime}';
  }
  return '${openList.length} days configured';
}

BranchWeekday? weekdayFromId(String id) {
  for (final entry in kWeekdays) {
    if (entry.id == id) {
      for (final day in BranchWeekday.values) {
        if (day.wireValue == id) {
          return day;
        }
      }
    }
  }
  return null;
}
