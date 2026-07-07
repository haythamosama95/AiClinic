import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_month_grid.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Selected date range (web `DateRange`).
@immutable
class AppDateRange {
  const AppDateRange({this.start, this.end});

  final DateTime? start;
  final DateTime? end;

  AppDateRange copyWith({DateTime? start, DateTime? end}) {
    return AppDateRange(start: start ?? this.start, end: end ?? this.end);
  }

  @override
  bool operator ==(Object other) {
    return other is AppDateRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

String _formatLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar' ? 'ar-EG' : 'en-GB';
}

String _formatRange(AppDateRange range, BuildContext context) {
  final fmt = DateFormat.MMMd(_formatLocale(context));
  if (range.start == null && range.end == null) return '';
  if (range.start != null && range.end == null) return fmt.format(range.start!);
  if (range.start != null && range.end != null) {
    return '${fmt.format(range.start!)} – ${fmt.format(range.end!)}';
  }
  return '';
}

/// Range calendar popover (web `DateRangePicker`).
class AppDateRangePicker extends StatefulWidget {
  const AppDateRangePicker({
    this.value,
    this.initialValue,
    this.onChanged,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Select date range',
    this.selectEndDateLabel = 'Select end date',
    this.inclusiveRangePrefix = 'Inclusive range:',
    this.previousLabel = 'Previous',
    this.nextLabel = 'Next',
    this.ariaLabelledBy,
    this.ariaDescribedBy,
    super.key,
  });

  final AppDateRange? value;
  final AppDateRange? initialValue;
  final ValueChanged<AppDateRange>? onChanged;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final String selectEndDateLabel;
  final String inclusiveRangePrefix;
  final String previousLabel;
  final String nextLabel;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;

  @override
  State<AppDateRangePicker> createState() => _AppDateRangePickerState();
}

class _AppDateRangePickerState extends State<AppDateRangePicker> {
  final _focusNode = FocusNode();
  var _open = false;
  var _focused = false;
  AppDateRange _internalValue = const AppDateRange();
  late DateTime _viewMonth;

  bool get _isControlled => widget.onChanged != null;

  AppDateRange get _range => _isControlled ? (widget.value ?? const AppDateRange()) : _internalValue;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue ?? const AppDateRange();
    _viewMonth = DateTime.now();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppDateRangePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled && widget.initialValue != null && widget.initialValue != oldWidget.initialValue) {
      _internalValue = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  void _setOpen(bool next) {
    if (widget.disabled) return;
    if (_open == next) return;
    setState(() => _open = next);
  }

  void _applyRange(AppDateRange next) {
    if (!_isControlled) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
    if (next.start != null && next.end != null) {
      _setOpen(false);
    }
  }

  void _handleSelect(DateTime day) {
    final range = _range;
    AppDateRange next;
    if (range.start == null || (range.start != null && range.end != null)) {
      next = AppDateRange(start: appDateOnly(day), end: null);
    } else if (day.isBefore(range.start!)) {
      next = AppDateRange(start: appDateOnly(day), end: appDateOnly(range.start!));
    } else {
      next = AppDateRange(start: appDateOnly(range.start!), end: appDateOnly(day));
    }
    _applyRange(next);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    });
  }

  String? _inclusiveMessage(BuildContext context) {
    final range = _range;
    final display = _formatRange(range, context);
    if (range.start != null && range.end != null) {
      return '${widget.inclusiveRangePrefix} $display';
    }
    if (range.start != null) {
      return widget.selectEndDateLabel;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(context, widget.size);
    final display = _formatRange(_range, context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon = isRtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;
    final inclusiveMsg = _inclusiveMessage(context);

    final popoverContent = Padding(
      padding: const EdgeInsets.all(AppSpacing.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MonthNavButton(icon: prevIcon, label: widget.previousLabel, onPressed: () => _shiftMonth(-1)),
              Expanded(
                child: Text(
                  '${_monthsEn[_viewMonth.month - 1]} ${_viewMonth.year}',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                ),
              ),
              _MonthNavButton(icon: nextIcon, label: widget.nextLabel, onPressed: () => _shiftMonth(1)),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          AppMonthGrid(
            month: _viewMonth,
            rangeStart: _range.start,
            rangeEnd: _range.end,
            showWeekdayHeaders: true,
            onDaySelect: _handleSelect,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          textField: true,
          enabled: !widget.disabled,
          identifier: widget.id,
          label: widget.placeholder,
          value: display.isEmpty ? null : display,
          child: AppPopover(
            open: _open && !widget.disabled,
            onOpenChange: _setOpen,
            matchTriggerWidth: false,
            width: 288,
            child: popoverContent,
            triggerBuilder: (context, isOpen, onToggle) => Focus(
              focusNode: _focusNode,
              child: GestureDetector(
                onTap: widget.disabled
                    ? null
                    : () {
                        _focusNode.requestFocus();
                        _setOpen(true);
                      },
                child: SizedBox(
                  height: metrics.height,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: metrics.height,
                        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
                        decoration: appInputDecoration(
                          context,
                          size: widget.size,
                          invalid: widget.invalid,
                          disabled: widget.disabled,
                          focused: _focused || isOpen,
                        ),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          display.isEmpty ? widget.placeholder : display,
                          style:
                              (display.isEmpty
                                      ? metrics.textStyle
                                      : appBareInputTextStyle(context, widget.size, disabled: widget.disabled))
                                  ?.copyWith(
                                    color: display.isEmpty
                                        ? colors.textPlaceholder
                                        : (widget.disabled ? colors.textDisabled : colors.textPrimary),
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PositionedDirectional(
                        end: AppSpacing.space3,
                        child: IgnorePointer(
                          child: Icon(Icons.calendar_today_outlined, size: metrics.iconSize, color: colors.iconMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (inclusiveMsg != null) ...[
          const SizedBox(height: AppSpacing.space1),
          Semantics(
            liveRegion: true,
            child: Text(inclusiveMsg, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
          ),
        ],
      ],
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
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          hoverColor: colors.surfaceHover,
        ),
      ),
    );
  }
}
