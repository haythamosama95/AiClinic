import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_month_grid.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Popover month picker for jumping the calendar to a specific date.
class AppCalendarDateJumpPopover extends StatefulWidget {
  const AppCalendarDateJumpPopover({
    required this.currentDate,
    required this.onDateSelected,
    required this.triggerBuilder,
    this.align = AppPopoverAlign.start,
    super.key,
  });

  final DateTime currentDate;
  final ValueChanged<DateTime> onDateSelected;
  final AppPopoverTriggerBuilder triggerBuilder;
  final AppPopoverAlign align;

  @override
  State<AppCalendarDateJumpPopover> createState() => _AppCalendarDateJumpPopoverState();
}

class _AppCalendarDateJumpPopoverState extends State<AppCalendarDateJumpPopover> {
  var _open = false;
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(widget.currentDate.year, widget.currentDate.month);
  }

  @override
  void didUpdateWidget(covariant AppCalendarDateJumpPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_open && !appIsSameDay(widget.currentDate, oldWidget.currentDate)) {
      _viewMonth = DateTime(widget.currentDate.year, widget.currentDate.month);
    }
  }

  void _select(DateTime date) {
    widget.onDateSelected(DateTime(date.year, date.month, date.day));
    setState(() => _open = false);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon = isRtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;
    final locale = Localizations.localeOf(context).languageCode == 'ar' ? 'ar-EG' : 'en-GB';
    final monthLabel = DateFormat.yMMMM(locale).format(_viewMonth);

    return AppPopover(
      open: _open,
      onOpenChange: (open) => setState(() {
        _open = open;
        if (open) {
          _viewMonth = DateTime(widget.currentDate.year, widget.currentDate.month);
        }
      }),
      align: widget.align,
      matchTriggerWidth: false,
      width: 288,
      estimatedContentHeight: 320,
      triggerBuilder: widget.triggerBuilder,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _MonthNavButton(icon: prevIcon, label: 'Previous month', onPressed: () => _shiftMonth(-1)),
                Expanded(
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                  ),
                ),
                _MonthNavButton(icon: nextIcon, label: 'Next month', onPressed: () => _shiftMonth(1)),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            AppMonthGrid(
              month: _viewMonth,
              selectedDate: widget.currentDate,
              showWeekdayHeaders: true,
              onDaySelect: _select,
            ),
          ],
        ),
      ),
    );
  }
}

/// Default popover trigger for jumping to a date from a calendar header title.
class AppCalendarDateJumpTitleTrigger extends StatelessWidget {
  const AppCalendarDateJumpTitleTrigger({required this.title, required this.isOpen, required this.onToggle, super.key});

  final String title;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppButton(
      size: AppButtonSize.sm,
      variant: isOpen ? AppButtonVariant.secondary : AppButtonVariant.ghost,
      onPressed: onToggle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(title, style: AppTypography.bodyStrong(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.space1),
          Icon(Icons.calendar_today_outlined, size: 16, color: colors.iconMuted),
        ],
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: colors.textPrimary),
        padding: const EdgeInsets.all(AppSpacing.space1),
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
      ),
    );
  }
}
