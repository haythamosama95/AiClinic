import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_calendar_mode.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';
import 'package:ai_clinic/features/shifts/presentation/utils/shift_presentation_formatting.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_month_day_sheet.dart';

/// Calendar panel with filters and [AppCalendar] bound to [shiftCalendarProvider].
class ShiftCalendarPanel extends ConsumerWidget {
  const ShiftCalendarPanel({
    this.title = 'Shift calendar',
    this.description,
    this.onCreateTap,
    super.key,
  });

  final String title;
  final String? description;
  final VoidCallback? onCreateTap;

  static const _modeOptions = [
    AppSegmentedOption(value: ShiftCalendarMode.week, label: 'Week'),
    AppSegmentedOption(value: ShiftCalendarMode.month, label: 'Month'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shiftCalendarProvider);
    final controller = ref.read(shiftCalendarProvider.notifier);
    final events = ShiftPresentationFormatting.toCalendarEvents(context, state.items);

    final contentState = switch (true) {
      _ when state.loading && state.items.isEmpty => AppContentState.loading,
      _ when state.error != null && state.items.isEmpty => AppContentState.error,
      _ when !state.loading && state.items.isEmpty => AppContentState.emptyFirstRun,
      _ => AppContentState.ready,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppToolbar(
          start: AppSegmentedControl<ShiftCalendarMode>(
            key: const Key('shift_calendar_mode_toggle'),
            options: _modeOptions,
            value: state.mode,
            onChanged: controller.setMode,
            semanticLabel: 'Shift calendar mode',
            size: AppSegmentedControlSize.sm,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppSectionHeader(
          title: title,
          description: description ?? ShiftPresentationFormatting.formatPeriodLabel(context, state),
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                key: const Key('shift_calendar_previous'),
                icon: LucideIcons.chevronLeft,
                semanticLabel: 'Previous period',
                onPressed: controller.previousPeriod,
              ),
              AppButton(
                key: const Key('shift_calendar_today'),
                label: 'Today',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: controller.goToToday,
              ),
              AppIconButton(
                key: const Key('shift_calendar_next'),
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
              emptyFirstRunTitle: 'No shifts scheduled',
              emptyFirstRunDescription: onCreateTap == null
                  ? 'No shifts are scheduled for this period.'
                  : 'No shifts are scheduled for this period. Create the first shift to start planning coverage.',
              emptyFirstRunActionLabel: onCreateTap == null ? null : 'Create shift',
              onEmptyFirstRunAction: onCreateTap,
            ),
            child: AppCalendar(
              events: events,
              view: ShiftPresentationFormatting.calendarViewFor(state.mode),
              selectedDate: state.focusDate,
              onDateChanged: controller.setFocusDate,
              onViewChanged: (view) => controller.setMode(ShiftPresentationFormatting.calendarModeFor(view)),
              onEventTap: (event) => _onEventTap(context, event.id, state.items, state.mode),
              onCreate: onCreateTap == null ? null : (_) => onCreateTap!(),
              startHour: 6,
              endHour: 22,
            ),
          ),
        ),
      ],
    );
  }

  void _onEventTap(BuildContext context, String eventId, List<ShiftListItem> items, ShiftCalendarMode mode) {
    final item = items.where((entry) => entry.id == eventId).firstOrNull;
    if (item == null) {
      return;
    }

    if (mode == ShiftCalendarMode.month) {
      final day = DateTime(item.shiftDate.year, item.shiftDate.month, item.shiftDate.day);
      final dayShifts = items.where((shift) {
        final shiftDay = DateTime(shift.shiftDate.year, shift.shiftDate.month, shift.shiftDate.day);
        return shiftDay == day;
      }).toList(growable: false)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      if (dayShifts.length > 1) {
        ShiftMonthDaySheet.show(context, date: day, shifts: dayShifts);
        return;
      }
    }

    context.push(AppRoutes.shiftDetail(item.id));
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
