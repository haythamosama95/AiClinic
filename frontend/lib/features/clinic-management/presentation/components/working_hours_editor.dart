import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';

/// Per-day working hours editor (web `WorkingHoursEditor`).
class WorkingHoursEditor extends StatelessWidget {
  const WorkingHoursEditor({
    required this.schedule,
    required this.onChange,
    this.disabled = false,
    super.key,
  });

  final BranchWorkingSchedule schedule;
  final ValueChanged<BranchWorkingSchedule> onChange;
  final bool disabled;

  void _updateDay(
    BranchWeekday day, {
    bool? isWorkingDay,
    String? openTime,
    String? closeTime,
    bool clearTimes = false,
  }) {
    onChange(
      BranchWorkingSchedule(
        schedule.days
            .map((hours) {
              if (hours.day != day) {
                return hours;
              }
              if (clearTimes) {
                return BranchWorkingDayHours(
                  day: day,
                  isWorkingDay: isWorkingDay ?? hours.isWorkingDay,
                  openTime: null,
                  closeTime: null,
                );
              }
              return hours.copyWith(
                isWorkingDay: isWorkingDay,
                openTime: openTime,
                closeTime: closeTime,
              );
            })
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in kWeekdays)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space2),
            child: _DayRow(
              label: entry.label,
              hours: schedule.days.firstWhere((day) => day.day.wireValue == entry.id),
              disabled: disabled,
              colors: colors,
              onChanged: (patch) {
                final weekday = BranchWeekday.values.firstWhere((day) => day.wireValue == entry.id);
                if (patch.isWorkingDay == false) {
                  _updateDay(weekday, isWorkingDay: false, clearTimes: true);
                  return;
                }
                _updateDay(
                  weekday,
                  isWorkingDay: patch.isWorkingDay,
                  openTime: patch.openTime,
                  closeTime: patch.closeTime,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DayPatch {
  const _DayPatch({this.isWorkingDay, this.openTime, this.closeTime});

  final bool? isWorkingDay;
  final String? openTime;
  final String? closeTime;
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.hours,
    required this.disabled,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final BranchWorkingDayHours hours;
  final bool disabled;
  final AppSemanticColors colors;
  final ValueChanged<_DayPatch> onChanged;

  @override
  Widget build(BuildContext context) {
    final isOpen = hours.isWorkingDay;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: Wrap(
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 128,
              child: Row(
                children: [
                  AppSwitch(
                    value: isOpen,
                    disabled: disabled,
                    onChanged: (checked) {
                      onChanged(
                        _DayPatch(
                          isWorkingDay: checked,
                          openTime: checked ? (hours.openTime ?? '09:00') : null,
                          closeTime: checked ? (hours.closeTime ?? '17:00') : null,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodySm(context).copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isOpen)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 112,
                    child: AppTimePicker(
                      value: hours.openTime,
                      use24Hour: true,
                      placeholder: 'Open',
                      disabled: disabled,
                      onChanged: (openTime) => onChanged(_DayPatch(openTime: openTime)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                    child: Text('–', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary)),
                  ),
                  SizedBox(
                    width: 112,
                    child: AppTimePicker(
                      value: hours.closeTime,
                      use24Hour: true,
                      placeholder: 'Close',
                      disabled: disabled,
                      onChanged: (closeTime) => onChanged(_DayPatch(closeTime: closeTime)),
                    ),
                  ),
                ],
              )
            else
              Text('Closed', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary)),
          ],
        ),
      ),
    );
  }
}
