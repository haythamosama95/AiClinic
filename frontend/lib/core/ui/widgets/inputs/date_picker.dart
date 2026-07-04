import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/picker_trigger.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Calendar grid helper shared by date pickers.
class AppCalendarGrid extends StatelessWidget {
  const AppCalendarGrid({
    super.key,
    required this.viewMonth,
    required this.selected,
    required this.onSelect,
    this.rangeStart,
    this.rangeEnd,
    this.min,
    this.max,
    this.localeCode = 'en',
  });

  final DateTime viewMonth;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? min;
  final DateTime? max;
  final String localeCode;

  static const _weekdaysEn = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  static const _weekdaysAr = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime?> _buildDays() {
    final year = viewMonth.year;
    final month = viewMonth.month;
    final first = DateTime(year, month, 1);
    final startPad = first.weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < startPad; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(year, month, d));
    }
    return cells;
  }

  bool _inRange(DateTime day) {
    if (rangeStart == null || rangeEnd == null) return false;
    final start = DateTime(
      rangeStart!.year,
      rangeStart!.month,
      rangeStart!.day,
    );
    final end = DateTime(rangeEnd!.year, rangeEnd!.month, rangeEnd!.day);
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final weekdays = localeCode == 'ar' ? _weekdaysAr : _weekdaysEn;
    final days = _buildDays();
    final today = DateTime.now();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final d in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: typography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: AppSpacing.s1,
            crossAxisSpacing: AppSpacing.s1,
          ),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final day = days[i];
            if (day == null) return const SizedBox.shrink();

            final disabled =
                (min != null && day.isBefore(min!)) ||
                (max != null && day.isAfter(max!));
            final isSelected = selected != null && isSameDay(day, selected!);
            final isToday = isSameDay(day, today);
            final inRange = _inRange(day);
            final isRangeEndpoint =
                (rangeStart != null && isSameDay(day, rangeStart!)) ||
                (rangeEnd != null && isSameDay(day, rangeEnd!));

            return Material(
              color: isSelected || isRangeEndpoint
                  ? colors.actionPrimary
                  : inRange
                  ? colors.surfaceSelected
                  : Colors.transparent,
              borderRadius: AppRadius.mdAll,
              child: InkWell(
                onTap: disabled ? null : () => onSelect(day),
                borderRadius: AppRadius.mdAll,
                child: Container(
                  alignment: Alignment.center,
                  decoration: isToday && !isSelected && !isRangeEndpoint
                      ? BoxDecoration(
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(color: colors.borderFocus),
                        )
                      : null,
                  child: Text(
                    '${day.day}',
                    style: typography.bodySm.copyWith(
                      color: disabled
                          ? colors.textDisabled
                          : isSelected || isRangeEndpoint
                          ? colors.actionPrimaryFg
                          : colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Single-date picker with calendar popover and typed entry.
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.value,
    this.min,
    this.max,
    this.placeholder = 'dd/mm/yyyy',
    this.localeCode,
    this.onValueChange,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final DateTime? value;
  final DateTime? min;
  final DateTime? max;
  final String placeholder;
  final String? localeCode;
  final ValueChanged<DateTime?>? onValueChange;

  @override
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  late TextEditingController _controller;
  late DateTime _viewMonth;
  bool _open = false;

  String get _locale {
    final code =
        widget.localeCode ?? Localizations.localeOf(context).languageCode;
    return code == 'ar' ? 'ar-EG' : 'en-GB';
  }

  String _format(DateTime date) => DateFormat('d MMM y', _locale).format(date);

  DateTime? _parse(String raw) {
    final parts = raw.split(RegExp(r'[/.-]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    final date = DateTime(y, m, d);
    return date.year == y && date.month == m && date.day == d ? date : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value != null ? _format(widget.value!) : '',
    );
    _viewMonth = widget.value ?? DateTime.now();
  }

  @override
  void didUpdateWidget(AppDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value != null ? _format(widget.value!) : '';
      if (widget.value != null) _viewMonth = widget.value!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(DateTime date) {
    if (widget.min != null && date.isBefore(widget.min!)) return;
    if (widget.max != null && date.isAfter(widget.max!)) return;
    widget.onValueChange?.call(date);
    _controller.text = _format(date);
    setState(() {
      _open = false;
      _viewMonth = date;
    });
  }

  IconData _prevIcon(BuildContext context) =>
      context.isRtl ? Icons.chevron_right : Icons.chevron_left;

  IconData _nextIcon(BuildContext context) =>
      context.isRtl ? Icons.chevron_left : Icons.chevron_right;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    const months = [
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

    return AppPopover(
      open: _open && !widget.disabled && !widget.readOnly,
      onOpenChange: (v) => setState(() => _open = v),
      contentPadding: const EdgeInsets.all(AppSpacing.s3),
      trigger: Focus(
        onFocusChange: (f) {
          if (f) setState(() => _open = true);
        },
        child: appPickerTriggerShell(
          context: context,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          focused: _open,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TextField(
                controller: _controller,
                enabled: !widget.disabled,
                readOnly: widget.readOnly,
                style: AppInputStyles.textStyle(
                  context,
                  widget.size,
                ).copyWith(color: colors.textPrimary),
                cursorColor: colors.borderFocus,
                decoration: AppInputStyles.bareInputDecoration(
                  context,
                  hintText: widget.placeholder,
                  disabled: widget.disabled,
                ),
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) _select(parsed);
                },
                onTap: () => setState(() => _open = true),
              ),
              PositionedDirectional(
                end: AppSpacing.s3,
                child: IgnorePointer(
                  child: Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: colors.iconMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      content: SizedBox(
        width: 288,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_prevIcon(context), size: 18),
                  onPressed: () => setState(() {
                    _viewMonth = DateTime(
                      _viewMonth.year,
                      _viewMonth.month - 1,
                      1,
                    );
                  }),
                  tooltip: 'Previous month',
                ),
                Expanded(
                  child: Text(
                    '${months[_viewMonth.month - 1]} ${_viewMonth.year}',
                    style: typography.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: Icon(_nextIcon(context), size: 18),
                  onPressed: () => setState(() {
                    _viewMonth = DateTime(
                      _viewMonth.year,
                      _viewMonth.month + 1,
                      1,
                    );
                  }),
                  tooltip: 'Next month',
                ),
              ],
            ),
            AppCalendarGrid(
              viewMonth: _viewMonth,
              selected: widget.value,
              min: widget.min,
              max: widget.max,
              localeCode: widget.localeCode ?? AppLocale.en.name,
              onSelect: _select,
            ),
          ],
        ),
      ),
    );
  }
}
