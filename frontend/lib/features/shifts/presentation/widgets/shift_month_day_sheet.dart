import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/presentation/utils/shift_presentation_formatting.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Lists all shifts on a selected day in month view (V1-7 US2).
class ShiftMonthDaySheet extends StatelessWidget {
  const ShiftMonthDaySheet({required this.date, required this.shifts, super.key});

  final DateTime date;
  final List<ShiftListItem> shifts;

  static Future<void> show(BuildContext context, {required DateTime date, required List<ShiftListItem> shifts}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ShiftMonthDaySheet(date: date, shifts: shifts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s4, 0, AppSpacing.s4, AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ShiftPresentationFormatting.formatDate(date),
              style: typography.title.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s3),
            if (shifts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
                child: Text(
                  'No shifts on this day.',
                  style: typography.body.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: shifts.length,
                  separatorBuilder: (_, _) => const AppDivider(),
                  itemBuilder: (context, index) {
                    final shift = shifts[index];
                    return ListTile(
                      key: Key('shift_month_day_item_${shift.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(ShiftPresentationFormatting.formatTimeRange(shift.startTime, shift.endTime)),
                      subtitle: Text(shift.assigneeSummary),
                      trailing: shift.isUnassigned
                          ? ShiftStatusBadge(status: shift.status, isUnassigned: true)
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push(AppRoutes.shiftDetail(shift.id));
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
