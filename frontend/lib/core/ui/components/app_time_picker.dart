import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

int? _parseTimeToMinutes(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final match24 = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(trimmed);
  if (match24 != null) {
    return int.parse(match24.group(1)!) * 60 + int.parse(match24.group(2)!);
  }

  final match12 = RegExp(r'^(\d{1,2}):([0-5]\d)\s*(AM|PM)$', caseSensitive: false).firstMatch(trimmed);
  if (match12 != null) {
    var hour = int.parse(match12.group(1)!);
    final minute = int.parse(match12.group(2)!);
    final period = match12.group(3)!.toUpperCase();
    if (hour < 1 || hour > 12) {
      return null;
    }
    if (period == 'PM' && hour != 12) {
      hour += 12;
    } else if (period == 'AM' && hour == 12) {
      hour = 0;
    }
    return hour * 60 + minute;
  }

  return null;
}

String _formatTime(int minutes, {required bool use24Hour}) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  if (use24Hour) {
    return '${_pad(hour)}:${_pad(minute)}';
  }
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${_pad(minute)} $period';
}

String _format24Hour(int minutes) => _formatTime(minutes, use24Hour: true);

List<String> _generateSlots({required int stepMinutes, required bool use24Hour}) {
  final slots = <String>[];
  for (var h = 0; h < 24; h++) {
    for (var m = 0; m < 60; m += stepMinutes) {
      final time24 = '${_pad(h)}:${_pad(m)}';
      if (use24Hour) {
        slots.add(time24);
      } else {
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        slots.add('$h12:${_pad(m)} $period');
      }
    }
  }
  return slots;
}

bool _isArabicLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar';
}

/// Scrollable time list popover (web `TimePicker`).
class AppTimePicker extends StatefulWidget {
  const AppTimePicker({
    this.value,
    this.initialValue,
    this.onChanged,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.stepMinutes = 15,
    this.use24Hour,
    this.placeholder = 'Select time',
    this.ariaLabelledBy,
    this.ariaDescribedBy,
    super.key,
  });

  final String? value;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final int stepMinutes;
  final bool? use24Hour;
  final String placeholder;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;

  @override
  State<AppTimePicker> createState() => _AppTimePickerState();
}

class _AppTimePickerState extends State<AppTimePicker> {
  final _focusNode = FocusNode();
  var _open = false;
  var _focused = false;
  String? _internalValue;

  bool get _isControlled => widget.onChanged != null;

  String get _value => _isControlled ? (widget.value ?? '') : (_internalValue ?? '');

  bool get _interactionDisabled => widget.disabled || widget.readOnly;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled &&
        widget.initialValue != oldWidget.initialValue &&
        (_internalValue == null || _internalValue!.isEmpty)) {
      _internalValue = widget.initialValue;
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
    if (_interactionDisabled) return;
    if (_open == next) return;
    setState(() => _open = next);
  }

  void _select(String time) {
    final minutes = _parseTimeToMinutes(time);
    final canonical = minutes == null ? time : _format24Hour(minutes);
    if (!_isControlled) {
      setState(() => _internalValue = canonical);
    }
    widget.onChanged?.call(canonical);
    _setOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(context, widget.size);
    final is24 = widget.use24Hour ?? !_isArabicLocale(context);
    final slots = _generateSlots(stepMinutes: widget.stepMinutes, use24Hour: is24);
    final valueMinutes = _parseTimeToMinutes(_value);
    final displayValue = valueMinutes == null ? _value : _formatTime(valueMinutes, use24Hour: is24);

    final listbox = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.space1),
        shrinkWrap: true,
        children: [
          for (final slot in slots)
            Semantics(
              button: true,
              selected: valueMinutes != null && _parseTimeToMinutes(slot) == valueMinutes,
              label: slot,
              child: Material(
                color: valueMinutes != null && _parseTimeToMinutes(slot) == valueMinutes
                    ? colors.surfaceSelected
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => _select(slot),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                    child: Text(
                      slot,
                      style: AppTypography.body(
                        context,
                      ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      textField: true,
      enabled: !widget.disabled,
      identifier: widget.id,
      label: widget.placeholder,
      value: displayValue.isEmpty ? null : displayValue,
      child: AppPopover(
        open: _open && !_interactionDisabled,
        onOpenChange: _setOpen,
        matchTriggerWidth: false,
        width: 192,
        child: Semantics(label: 'Time options', child: listbox),
        triggerBuilder: (context, isOpen, onToggle) => Focus(
          focusNode: _focusNode,
          child: GestureDetector(
            onTap: _interactionDisabled
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
                      readOnly: widget.readOnly,
                      focused: _focused || isOpen,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      displayValue.isEmpty ? widget.placeholder : displayValue,
                      style:
                          (displayValue.isEmpty
                                  ? metrics.textStyle
                                  : appBareInputTextStyle(context, widget.size, disabled: widget.disabled))
                              ?.copyWith(
                                color: displayValue.isEmpty
                                    ? colors.textPlaceholder
                                    : (widget.disabled ? colors.textDisabled : colors.textPrimary),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                    ),
                  ),
                  PositionedDirectional(
                    end: AppSpacing.space3,
                    child: IgnorePointer(
                      child: Icon(Icons.schedule_outlined, size: metrics.iconSize, color: colors.iconMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
