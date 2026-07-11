import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_time_picker.dart';
import 'package:ai_clinic/core/ui/components/app_tooltip.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_field_hints.dart';

/// Seven-day working hours editor (web `WorkingHoursEditor`).
class WorkingHoursEditor extends StatelessWidget {
  const WorkingHoursEditor({required this.value, required this.onChange, this.errors, super.key});

  final List<WorkingDay> value;
  final ValueChanged<List<WorkingDay>> onChange;
  final Map<String, String>? errors;

  void _updateDay(String dayId, WorkingDay patch) {
    onChange(value.map((day) => day.day == dayId ? patch : day).toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabledCount = value.where((day) => day.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Working days & hours', style: AppTypography.bodyStrong(context)),
            const SizedBox(width: AppSpacing.space2),
            AppTooltip(
              message: SetupFieldHints.branchWorkingHours,
              preferBelow: false,
              child: Semantics(
                button: true,
                label: 'More about Working days & hours',
                child: IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.help_outline, size: 16, color: colors.iconMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 20, height: 20),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              '$enabledCount day${enabledCount == 1 ? '' : 's'} open',
              style: AppTypography.caption(
                context,
              ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space3),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.borderDefault),
            color: colors.surfaceDefault,
          ),
          child: Column(
            children: [
              for (var i = 0; i < DAYS_OF_WEEK.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: colors.borderSubtle),
                _WorkingDayRow(
                  dayMeta: DAYS_OF_WEEK[i],
                  day: value.firstWhere((d) => d.day == DAYS_OF_WEEK[i].id),
                  timeError: errors?['${DAYS_OF_WEEK[i].id}-time'],
                  onUpdate: (patch) => _updateDay(DAYS_OF_WEEK[i].id, patch),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkingDayRow extends StatelessWidget {
  const _WorkingDayRow({required this.dayMeta, required this.day, required this.onUpdate, this.timeError});

  final DayOfWeekMeta dayMeta;
  final WorkingDay day;
  final ValueChanged<WorkingDay> onUpdate;
  final String? timeError;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 480;

              final labelRow = Row(
                children: [
                  AppCheckbox(
                    value: day.enabled ? AppCheckboxState.checked : AppCheckboxState.unchecked,
                    onChanged: (state) {
                      onUpdate(day.copyWith(enabled: state == AppCheckboxState.checked));
                    },
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  SizedBox(
                    width: 112,
                    child: Text(
                      dayMeta.label,
                      style: AppTypography.body(context).copyWith(
                        color: day.enabled ? colors.textPrimary : colors.textTertiary,
                        fontWeight: day.enabled ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              );

              final schedule = day.enabled
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 112,
                          child: AppTimePicker(
                            value: day.openTime,
                            onChanged: (openTime) => onUpdate(day.copyWith(openTime: openTime)),
                            size: AppInputSize.sm,
                            use24Hour: false,
                            ariaLabelledBy: '${dayMeta.id}-open-label',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                          child: Text('to', style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
                        ),
                        SizedBox(
                          width: 112,
                          child: AppTimePicker(
                            value: day.closeTime,
                            onChanged: (closeTime) => onUpdate(day.copyWith(closeTime: closeTime)),
                            size: AppInputSize.sm,
                            use24Hour: false,
                            ariaLabelledBy: '${dayMeta.id}-close-label',
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Closed',
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      textAlign: isWide ? TextAlign.end : TextAlign.start,
                    );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [labelRow, const Spacer(), schedule],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelRow,
                  const SizedBox(height: AppSpacing.space3),
                  schedule,
                ],
              );
            },
          ),
          if (timeError != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              timeError!,
              style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg),
              textAlign: TextAlign.end,
            ),
          ],
        ],
      ),
    );
  }
}
