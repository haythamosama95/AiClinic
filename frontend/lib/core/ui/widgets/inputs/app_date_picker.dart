import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_calendar_shared.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Single-date picker with calendar popover and keyboard entry.
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    this.value,
    this.defaultValue,
    this.onChanged,
    this.min,
    this.max,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.placeholder = 'dd/mm/yyyy',
    this.controller,
    this.focusNode,
    super.key,
  });

  final DateTime? value;
  final DateTime? defaultValue;
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? min;
  final DateTime? max;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  late AppPopoverController _popoverController;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  DateTime? _internal;
  late DateTime _viewMonth;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _internal = widget.defaultValue;
    final initial = widget.value ?? _internal;
    _viewMonth = initial ?? DateTime.now();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyDisplayToField();
    });
  }

  @override
  void didUpdateWidget(covariant AppDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null && _text.isEmpty) {
      _internal = widget.value;
      _viewMonth = widget.value!;
      _applyDisplayToField();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }

  DateTime? get _value => widget.value ?? _internal;

  bool get _interactive => !widget.disabled && !widget.readOnly;

  void _applyDisplayToField() {
    final v = _value;
    if (_text.isNotEmpty && _focusNode.hasFocus) return;
    final display = v != null ? appCalendarFormatDisplayDate(context, v) : '';
    _text = display;
    if (_controller.text != display) {
      _controller.text = display;
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus && _interactive) {
      _popoverController.show();
    }
    if (!_focusNode.hasFocus) {
      _text = '';
      _applyDisplayToField();
    }
  }

  void _commitText(String raw) {
    _text = raw;
    final parsed = appCalendarParseDdMmYyyy(raw);
    if (parsed == null) return;
    if (widget.min != null &&
        appCalendarStartOfDay(parsed).isBefore(appCalendarStartOfDay(widget.min!))) {
      return;
    }
    if (widget.max != null &&
        appCalendarStartOfDay(parsed).isAfter(appCalendarStartOfDay(widget.max!))) {
      return;
    }
    _select(parsed, close: false);
  }

  void _select(DateTime date, {bool close = true}) {
    final normalized = appCalendarStartOfDay(date);
    if (widget.value == null) {
      setState(() => _internal = normalized);
    }
    widget.onChanged?.call(normalized);
    _text = '';
    _controller.text = appCalendarFormatDisplayDate(context, normalized);
    _viewMonth = normalized;
    if (close) _popoverController.hide();
    setState(() {});
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPopover(
      controller: _popoverController,
      placement: AppPopoverPlacement.bottomStart,
      onOpenChange: (_) => setState(() {}),
      trigger: (context, show, hide, toggle) {
        return AppInputFrame(
          focusNode: _focusNode,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          trailing: const AppInputIconSlot(icon: LucideIcons.calendar),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !widget.disabled,
            readOnly: widget.readOnly,
            style: appBareInputTextStyle(
              context,
              size: widget.size,
              disabled: widget.disabled,
              readOnly: widget.readOnly,
            ),
            decoration: appBareInputDecoration(
              context: context,
              size: widget.size,
              hintText: widget.placeholder,
              disabled: widget.disabled,
              readOnly: widget.readOnly,
            ),
            cursorColor: context.colors.borderFocus,
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9/.-]')),
            ],
            onChanged: (text) => _commitText(text),
            onTap: () {
              if (_interactive) _popoverController.show();
            },
          ),
        );
      },
      content: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: SizedBox(
            width: 288,
            child: AppCalendarGrid(
              month: _viewMonth,
              selectedDay: _value,
              min: widget.min,
              max: widget.max,
              onDaySelected: (day) => _select(day),
              onPreviousMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
            ),
          ),
        );
      },
    );
  }
}
