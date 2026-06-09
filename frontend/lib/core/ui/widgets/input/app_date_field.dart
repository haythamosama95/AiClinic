import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_field_size.dart';

/// Date field presentation mode.
enum AppDateFieldMode { input, calendar, combined }

/// Application date field wrapping [FDateField].
class AppDateField extends StatefulWidget {
  const AppDateField({
    required this.label,
    this.value,
    this.onChanged,
    this.hintText,
    this.description,
    this.validator,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.mode = AppDateFieldMode.combined,
    this.firstDate,
    this.lastDate,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final String? hintText;
  final String? description;
  final String? Function(DateTime?)? validator;
  final bool enabled;
  final AppFieldSize size;
  final AppDateFieldMode mode;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final FDateFieldController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FDateFieldController(date: widget.value, validator: widget.validator ?? (_) => null);
    _controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.value) {
      _controller.value = widget.value;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    widget.onChanged?.call(_controller.value);
  }

  FDateFieldControl _control() {
    return FDateFieldControl.managed(controller: _controller);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final control = _control();

    final labelWidget = Text(widget.label, style: theme.textTheme.labelMedium);
    final descriptionWidget = widget.description == null
        ? null
        : Text(widget.description!, style: theme.textTheme.bodySmall);

    return switch (widget.mode) {
      AppDateFieldMode.input => FDateField.input(
        control: control,
        size: widget.size.forui,
        label: labelWidget,
        description: descriptionWidget,
        enabled: widget.enabled,
      ),
      AppDateFieldMode.calendar => FDateField.calendar(
        control: control,
        size: widget.size.forui,
        label: labelWidget,
        description: descriptionWidget,
        hint: widget.hintText,
        enabled: widget.enabled,
        start: widget.firstDate,
        end: widget.lastDate,
      ),
      AppDateFieldMode.combined => FDateField(
        control: control,
        size: widget.size.forui,
        label: labelWidget,
        description: descriptionWidget,
        enabled: widget.enabled,
        calendar: FDateFieldCalendarProperties(start: widget.firstDate, end: widget.lastDate),
      ),
    };
  }
}

/// Application time field wrapping [FTimeField].
class AppTimeField extends StatelessWidget {
  const AppTimeField({
    required this.label,
    this.value,
    this.onChanged,
    this.description,
    this.validator,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.use24Hour = false,
    this.usePicker = true,
    super.key,
  });

  final String label;
  final FTime? value;
  final ValueChanged<FTime?>? onChanged;
  final String? description;
  final String? Function(FTime?)? validator;
  final bool enabled;
  final AppFieldSize size;
  final bool use24Hour;
  final bool usePicker;

  FTimeFieldControl _control() {
    return FTimeFieldControl.managed(initial: value, onChange: onChanged, validator: validator);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final control = _control();

    final labelWidget = Text(label, style: theme.textTheme.labelMedium);
    final descriptionWidget = description == null ? null : Text(description!, style: theme.textTheme.bodySmall);

    if (usePicker) {
      return FTimeField.picker(
        control: control,
        size: size.forui,
        hour24: use24Hour,
        label: labelWidget,
        description: descriptionWidget,
        enabled: enabled,
      );
    }

    return FTimeField(
      control: control,
      size: size.forui,
      hour24: use24Hour,
      label: labelWidget,
      description: descriptionWidget,
      enabled: enabled,
    );
  }
}

/// Application date-time picker wrapping [FDateTimePicker].
class AppDateTimePicker extends StatelessWidget {
  const AppDateTimePicker({this.value, this.onChanged, this.use24Hour = false, super.key});

  final DateTime? value;
  final ValueChanged<DateTime>? onChanged;
  final bool use24Hour;

  @override
  Widget build(BuildContext context) {
    return FDateTimePicker(
      control: FDateTimePickerControl.lifted(dateTime: value ?? DateTime.now(), onChange: onChanged ?? (_) {}),
      hour24: use24Hour,
    );
  }
}
