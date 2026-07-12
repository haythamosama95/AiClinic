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

String _formatLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar' ? 'ar-EG' : 'en-GB';
}

String _formatDisplay(DateTime date, BuildContext context) {
  return DateFormat.yMMMd(_formatLocale(context)).format(date);
}

DateTime? _parseInput(String raw) {
  final parts = raw.split(RegExp(r'[/.-]')).map((part) => int.tryParse(part.trim())).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return null;
  final day = parts[0]!;
  final month = parts[1]!;
  final year = parts[2]!;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Calendar popover with typed entry (web `DatePicker`).
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    this.value,
    this.initialValue,
    this.onChanged,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.min,
    this.max,
    this.placeholder = 'dd/mm/yyyy',
    this.ariaLabelledBy,
    this.ariaDescribedBy,
    super.key,
  });

  final DateTime? value;
  final DateTime? initialValue;
  final ValueChanged<DateTime?>? onChanged;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final DateTime? min;
  final DateTime? max;
  final String placeholder;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;

  @override
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();
  var _open = false;
  var _focused = false;
  DateTime? _internalValue;
  late DateTime _viewMonth;
  var _editingText = false;

  bool get _isControlled => widget.onChanged != null;

  DateTime? get _value => _isControlled ? widget.value : _internalValue;

  bool get _interactionDisabled => widget.disabled || widget.readOnly;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
    _viewMonth = _value ?? widget.initialValue ?? DateTime.now();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_editingText) {
      _syncTextFromValue();
    }
  }

  @override
  void didUpdateWidget(covariant AppDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled && widget.initialValue != oldWidget.initialValue && _internalValue == null) {
      _internalValue = widget.initialValue;
    }
    if (_isControlled && !_editingText) {
      final newValue = widget.value;
      final oldValue = oldWidget.value;
      final valueChanged = newValue == null
          ? oldValue != null
          : oldValue == null
          ? true
          : !appIsSameDay(newValue, oldValue);
      if (valueChanged) {
        _syncTextFromValue();
        if (newValue != null) {
          _viewMonth = newValue;
        }
      }
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
    if (focused && !_interactionDisabled) {
      _setOpen(true);
    }
  }

  void _syncTextFromValue() {
    final value = _value;
    _controller.text = value == null ? '' : _formatDisplay(value, context);
  }

  void _setOpen(bool next) {
    if (_interactionDisabled) return;
    if (_open == next) return;
    setState(() => _open = next);
  }

  void _select(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (widget.min != null && appDateOnly(normalized).isBefore(appDateOnly(widget.min!))) return;
    if (widget.max != null && appDateOnly(normalized).isAfter(appDateOnly(widget.max!))) return;

    if (!_isControlled) {
      setState(() => _internalValue = normalized);
    }
    widget.onChanged?.call(normalized);
    _editingText = false;
    _controller.text = _formatDisplay(normalized, context);
    _setOpen(false);
  }

  void _handleTextChanged(String raw) {
    setState(() => _editingText = true);
    final parsed = _parseInput(raw);
    if (parsed != null) {
      _select(parsed);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(context, widget.size);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon = isRtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;

    final calendar = Padding(
      padding: const EdgeInsets.all(AppSpacing.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _MonthNavButton(icon: prevIcon, label: 'Previous month', onPressed: () => _shiftMonth(-1)),
              Expanded(
                child: Text(
                  '${_monthsEn[_viewMonth.month - 1]} ${_viewMonth.year}',
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
            selectedDate: _value,
            min: widget.min,
            max: widget.max,
            showWeekdayHeaders: true,
            onDaySelect: _select,
          ),
        ],
      ),
    );

    return Semantics(
      textField: true,
      enabled: !widget.disabled,
      identifier: widget.id,
      label: widget.placeholder,
      value: _controller.text.isEmpty ? null : _controller.text,
      child: AppPopover(
        open: _open && !_interactionDisabled,
        onOpenChange: _setOpen,
        matchTriggerWidth: false,
        width: 288,
        child: calendar,
        triggerBuilder: (context, isOpen, onToggle) => SizedBox(
          height: metrics.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              appWrapMaterialInput(
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !widget.disabled,
                  readOnly: widget.readOnly,
                  style: appBareInputTextStyle(context, widget.size, disabled: widget.disabled),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.placeholder,
                    hintStyle: appBareInputTextStyle(
                      context,
                      widget.size,
                      disabled: widget.disabled,
                    ).copyWith(color: colors.textPlaceholder),
                    contentPadding: EdgeInsetsDirectional.only(
                      start: metrics.horizontalPadding,
                      end: metrics.horizontalPadding + metrics.iconSize + AppSpacing.space2,
                      top: (metrics.height - (metrics.textStyle?.fontSize ?? 14)) / 2,
                      bottom: (metrics.height - (metrics.textStyle?.fontSize ?? 14)) / 2,
                    ),
                    filled: true,
                    fillColor: widget.disabled
                        ? colors.actionDisabledBg
                        : (widget.readOnly ? colors.surfaceSunken : colors.surfaceDefault),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: appInputBorder(
                        colors,
                        invalid: widget.invalid,
                        focused: _focused || isOpen,
                        brightness: Theme.of(context).brightness,
                      ).top,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: appInputBorder(
                        colors,
                        invalid: widget.invalid,
                        focused: true,
                        brightness: Theme.of(context).brightness,
                      ).top,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: colors.borderDefault),
                    ),
                  ),
                  onChanged: _handleTextChanged,
                  onTap: () {
                    if (!_interactionDisabled) _setOpen(true);
                  },
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
