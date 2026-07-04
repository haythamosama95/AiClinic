import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/picker_trigger.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Time slot picker with scrollable list popover.
class AppTimePicker extends StatefulWidget {
  const AppTimePicker({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.value,
    this.stepMinutes = 15,
    this.use24Hour,
    this.placeholder = 'Select time',
    this.localeCode,
    this.onValueChange,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? value;
  final int stepMinutes;
  final bool? use24Hour;
  final String placeholder;
  final String? localeCode;
  final ValueChanged<String>? onValueChange;

  @override
  State<AppTimePicker> createState() => _AppTimePickerState();
}

class _AppTimePickerState extends State<AppTimePicker> {
  bool _open = false;

  bool get _is24Hour {
    if (widget.use24Hour != null) return widget.use24Hour!;
    final code =
        widget.localeCode ?? Localizations.localeOf(context).languageCode;
    return code != 'ar';
  }

  List<String> _generateSlots() {
    final slots = <String>[];
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += widget.stepMinutes) {
        final time24 =
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        if (_is24Hour) {
          slots.add(time24);
        } else {
          final period = h >= 12 ? 'PM' : 'AM';
          final h12 = h % 12 == 0 ? 12 : h % 12;
          slots.add('$h12:${m.toString().padLeft(2, '0')} $period');
        }
      }
    }
    return slots;
  }

  void _select(String time) {
    widget.onValueChange?.call(time);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final slots = _generateSlots();

    return AppPopover(
      open: _open && !widget.disabled && !widget.readOnly,
      onOpenChange: (v) => setState(() => _open = v),
      contentPadding: const EdgeInsets.all(AppSpacing.s1),
      trigger: appPickerTriggerShell(
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
              readOnly: true,
              enabled: !widget.disabled,
              controller: TextEditingController(text: widget.value ?? ''),
              onTap: () {
                if (!widget.disabled && !widget.readOnly) {
                  setState(() => _open = true);
                }
              },
              style: AppInputStyles.textStyle(context, widget.size).copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              cursorColor: colors.borderFocus,
              decoration: AppInputStyles.bareInputDecoration(
                context,
                hintText: widget.placeholder,
                disabled: widget.disabled,
              ),
            ),
            PositionedDirectional(
              end: AppSpacing.s3,
              child: IgnorePointer(
                child: Icon(Icons.schedule, size: 18, color: colors.iconMuted),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 192,
        height: 240,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final selected = slot == widget.value;
            return Material(
              color: selected ? colors.surfaceSelected : Colors.transparent,
              child: InkWell(
                onTap: () => _select(slot),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3,
                    vertical: AppSpacing.s2,
                  ),
                  child: Text(
                    slot,
                    style: typography.body.copyWith(
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
