import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
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

  String _formatDate(BuildContext context) {
    return MaterialLocalizations.of(context).formatFullDate(date);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_formatDate(context), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (shifts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No shifts on this day.', style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: shifts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final shift = shifts[index];
                    return ListTile(
                      key: Key('shift_month_day_item_${shift.id}'),
                      title: Text('${shift.startTime}–${shift.endTime}'),
                      subtitle: Text(shift.assigneeSummary),
                      trailing: shift.isUnassigned ? ShiftStatusBadge(status: shift.status, isUnassigned: true) : null,
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
