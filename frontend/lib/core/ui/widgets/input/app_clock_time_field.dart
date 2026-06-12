import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'app_field_size.dart';
import 'app_label.dart';

/// Opens a clock-dial time picker dialog (no spinner) in 12-hour AM/PM mode.
Future<TimeOfDay?> showAppClockTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required String helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
    initialEntryMode: TimePickerEntryMode.dialOnly,
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false), child: child!),
  );
}

/// Time field that opens a Material clock dial with an AM/PM selector.
///
/// Unlike [AppTimeField], this never uses a spinner — only the analog clock face.
class AppClockTimeField extends StatefulWidget {
  const AppClockTimeField({
    required this.label,
    this.value,
    this.onChanged,
    this.hintText,
    this.description,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
    this.size = AppFieldSize.md,
    this.autovalidateMode,
    super.key,
  });

  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?>? onChanged;
  final String? hintText;
  final String? description;
  final String? Function(TimeOfDay?)? validator;
  final bool enabled;
  final bool readOnly;
  final AppFieldSize size;
  final AutovalidateMode? autovalidateMode;

  @override
  State<AppClockTimeField> createState() => _AppClockTimeFieldState();
}

class _AppClockTimeFieldState extends State<AppClockTimeField> {
  final _fieldKey = GlobalKey<FormFieldState<TimeOfDay?>>();

  @override
  void didUpdateWidget(covariant AppClockTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _fieldKey.currentState?.didChange(widget.value);
    }
  }

  AutovalidateMode get _autovalidateMode =>
      widget.autovalidateMode ??
      (widget.validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled);

  String _formatTime(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time, alwaysUse24HourFormat: false);
  }

  bool get _interactive => widget.enabled && !widget.readOnly;

  Future<void> _openTimePicker(FormFieldState<TimeOfDay?> field) async {
    if (!_interactive) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    final picked = await showAppClockTimePicker(
      context: context,
      helpText: widget.label,
      initialTime: field.value ?? TimeOfDay.now(),
    );

    if (!mounted || picked == null) {
      return;
    }

    field.didChange(picked);
    widget.onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<TimeOfDay?>(
      key: _fieldKey,
      initialValue: widget.value,
      validator: widget.validator,
      autovalidateMode: _autovalidateMode,
      builder: (field) {
        final theme = Theme.of(context);
        final colors = context.semanticColors;
        final selected = field.value;
        final hasValue = selected != null;
        final displayText = hasValue ? _formatTime(context, selected) : null;

        return AppLabel(
          label: widget.label,
          description: widget.description,
          error: field.errorText,
          child: MouseRegion(
            cursor: _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: InkWell(
              onTap: _interactive ? () => _openTimePicker(field) : null,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                isEmpty: !hasValue,
                isFocused: false,
                decoration: InputDecoration(
                  hintText: widget.hintText ?? 'Select time',
                  contentPadding: _fieldContentPadding(widget.size),
                  filled: true,
                  fillColor: _interactive ? colors.background : colors.muted,
                  suffixIcon: Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: _interactive
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                  ),
                  enabled: _interactive,
                  enabledBorder: field.hasError
                      ? theme.inputDecorationTheme.errorBorder
                      : theme.inputDecorationTheme.enabledBorder,
                  focusedBorder: field.hasError
                      ? theme.inputDecorationTheme.errorBorder
                      : theme.inputDecorationTheme.focusedBorder,
                  disabledBorder: theme.inputDecorationTheme.disabledBorder,
                  errorBorder: theme.inputDecorationTheme.errorBorder,
                ),
                child: hasValue
                    ? Text(
                        displayText!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: _interactive
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}

EdgeInsets _fieldContentPadding(AppFieldSize size) => switch (size) {
  AppFieldSize.sm => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  AppFieldSize.md => const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  AppFieldSize.lg => const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
};
