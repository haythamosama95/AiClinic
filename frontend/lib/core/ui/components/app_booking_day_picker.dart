import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Horizontal day chip row for appointment booking step 2.
///
/// Shows [visibleDayCount] consecutive days at a time. Left/right arrows page
/// backward and forward by that many days. Days before [today] are not shown.
class AppBookingDayPicker extends StatefulWidget {
  const AppBookingDayPicker({
    required this.today,
    required this.selectedDate,
    required this.onDateSelected,
    this.visibleDayCount = 7,
    this.errorText,
    super.key,
  });

  final DateTime today;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final int visibleDayCount;
  final String? errorText;

  @override
  State<AppBookingDayPicker> createState() => _AppBookingDayPickerState();
}

class _AppBookingDayPickerState extends State<AppBookingDayPicker> {
  late DateTime _windowStart;

  DateTime get _today => DateTime(widget.today.year, widget.today.month, widget.today.day);

  @override
  void initState() {
    super.initState();
    _windowStart = _initialWindowStart();
  }

  @override
  void didUpdateWidget(covariant AppBookingDayPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedDate;
    if (selected != null && !_isDateVisible(selected)) {
      _windowStart = _pageStartFor(selected);
    }
    if (_windowStart.isBefore(_today)) {
      _windowStart = _today;
    }
  }

  DateTime _initialWindowStart() {
    final selected = widget.selectedDate;
    if (selected != null) {
      return _pageStartFor(selected);
    }
    return _today;
  }

  DateTime _pageStartFor(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final offset = normalized.difference(_today).inDays;
    if (offset <= 0) {
      return _today;
    }
    final page = offset ~/ widget.visibleDayCount;
    return _today.add(Duration(days: page * widget.visibleDayCount));
  }

  List<DateTime> get _visibleDays {
    return List.generate(widget.visibleDayCount, (index) => _windowStart.add(Duration(days: index)));
  }

  bool _isDateVisible(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final lastVisible = _windowStart.add(Duration(days: widget.visibleDayCount - 1));
    return !normalized.isBefore(_windowStart) && !normalized.isAfter(lastVisible);
  }

  bool get _canGoPrevious => _windowStart.isAfter(_today);

  void _previousPage() {
    final nextStart = _windowStart.subtract(Duration(days: widget.visibleDayCount));
    setState(() {
      _windowStart = nextStart.isBefore(_today) ? _today : nextStart;
    });
  }

  void _nextPage() {
    setState(() {
      _windowStart = _windowStart.add(Duration(days: widget.visibleDayCount));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visibleDays = _visibleDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Day', style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.space2),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavigationArrow(
                icon: Icons.chevron_left,
                label: 'Previous days',
                onPressed: _canGoPrevious ? _previousPage : null,
              ),
              const SizedBox(width: AppSpacing.space1),
              Expanded(
                child: Semantics(
                  label: 'Select appointment day',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < visibleDays.length; index++) ...[
                        if (index > 0) const SizedBox(width: AppSpacing.space2),
                        Expanded(
                          child: _DayChip(
                            date: visibleDays[index],
                            selected:
                                widget.selectedDate != null && _isSameDay(visibleDays[index], widget.selectedDate!),
                            onPressed: () => widget.onDateSelected(visibleDays[index]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space1),
              _NavigationArrow(icon: Icons.chevron_right, label: 'Next days', onPressed: _nextPage),
            ],
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(widget.errorText!, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
        ],
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date, required this.selected, required this.onPressed});

  final DateTime date;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final weekday = DateFormat.E().format(date);
    final month = DateFormat.MMM().format(date);

    final background = selected ? colors.actionPrimary : colors.surfaceDefault;
    final foreground = selected ? colors.actionPrimaryFg : colors.textPrimary;
    final borderColor = selected ? colors.actionPrimary : colors.borderDefault;

    return AppPressable(
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: borderColor),
          boxShadow: selected ? [BoxShadow(color: colors.borderDefault.withValues(alpha: 0.2), blurRadius: 4)] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekday.toUpperCase(),
              style: AppTypography.caption(context).copyWith(color: foreground.withValues(alpha: 0.8), fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${date.day}',
              style: AppTypography.h3(
                context,
              ).copyWith(color: foreground, height: 1, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text(
              month,
              style: AppTypography.caption(context).copyWith(color: foreground.withValues(alpha: 0.8)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationArrow extends StatelessWidget {
  const _NavigationArrow({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final enabled = onPressed != null;

    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: AppPressable(
        onPressed: onPressed,
        enabled: enabled,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderDefault),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: enabled ? colors.textPrimary : colors.textTertiary),
        ),
      ),
    );
  }
}
