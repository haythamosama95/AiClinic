import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';

/// Popover control for the calendar time-slot grid interval.
class AppointmentCalendarTimeIntervalButton extends ConsumerStatefulWidget {
  const AppointmentCalendarTimeIntervalButton({super.key});

  @override
  ConsumerState<AppointmentCalendarTimeIntervalButton> createState() =>
      _AppointmentCalendarTimeIntervalButtonState();
}

class _AppointmentCalendarTimeIntervalButtonState
    extends ConsumerState<AppointmentCalendarTimeIntervalButton> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appointmentCalendarProvider);
    final controller = ref.read(appointmentCalendarProvider.notifier);
    final colors = context.appColors;
    final selectedMinutes = state.timeIntervalMinutes;

    return AppPopover(
      open: _open,
      onOpenChange: (open) => setState(() => _open = open),
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      minWidth: 180,
      width: 200,
      estimatedContentHeight: 180,
      triggerBuilder: (context, isOpen, onToggle) {
        return AppButton(
          size: AppButtonSize.sm,
          variant: isOpen ? AppButtonVariant.secondary : AppButtonVariant.ghost,
          onPressed: onToggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 16,
                color: colors.iconDefault,
              ),
              const SizedBox(width: AppSpacing.space1),
              Text(_intervalLabel(selectedMinutes)),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space2,
                AppSpacing.space1,
                AppSpacing.space2,
                AppSpacing.space2,
              ),
              child: Text(
                'Time interval',
                style: AppTypography.bodyStrong(context),
              ),
            ),
            for (final minutes
                in AppointmentCalendarDisplay.supportedTimeIntervalMinutes)
              _IntervalOption(
                minutes: minutes,
                selected: minutes == selectedMinutes,
                onSelected: () {
                  controller.setTimeIntervalMinutes(minutes);
                  setState(() => _open = false);
                },
              ),
            const SizedBox(height: AppSpacing.space1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space2,
              ),
              child: Text(
                'Controls the grid spacing for day, week, and doctor views.',
                style: AppTypography.caption(
                  context,
                ).copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _intervalLabel(int minutes) => '${minutes}m';
}

class _IntervalOption extends StatelessWidget {
  const _IntervalOption({
    required this.minutes,
    required this.selected,
    required this.onSelected,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: selected ? colors.surfaceSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space2,
            vertical: AppSpacing.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _label(minutes),
                  style: AppTypography.bodySm(context),
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 16, color: colors.actionPrimary),
            ],
          ),
        ),
      ),
    );
  }

  static String _label(int minutes) {
    return switch (minutes) {
      15 => '15 minutes',
      30 => '30 minutes',
      60 => '1 hour',
      _ => '$minutes minutes',
    };
  }
}
