import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Time-of-day picker with scrollable slot list.
class AppTimePicker extends StatefulWidget {
  const AppTimePicker({
    this.value,
    this.defaultValue,
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.stepMinutes = 15,
    this.use24Hour,
    this.placeholder = 'Select time',
    this.controller,
    this.focusNode,
    super.key,
  });

  final String? value;
  final String? defaultValue;
  final ValueChanged<String>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final int stepMinutes;
  final bool? use24Hour;
  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<AppTimePicker> createState() => _AppTimePickerState();
}

class _AppTimePickerState extends State<AppTimePicker> {
  late AppPopoverController _popoverController;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  String? _internal;
  List<String> _slots = [];

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _internal = widget.defaultValue;
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(text: _currentValue);
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _slots = _generateSlots());
    });
  }

  @override
  void didUpdateWidget(covariant AppTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stepMinutes != oldWidget.stepMinutes ||
        widget.use24Hour != oldWidget.use24Hour) {
      _slots = _generateSlots();
    }
    if (widget.value != oldWidget.value && widget.value != null) {
      _controller.text = widget.value!;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }

  String? get _currentValue => widget.value ?? _internal;

  bool get _interactive => !widget.disabled && !widget.readOnly;

  bool _resolve24Hour(BuildContext context) {
    if (widget.use24Hour != null) return widget.use24Hour!;
    return !appInputIsArabic(context);
  }

  List<String> _generateSlots() {
    final use24 = _resolve24Hour(context);
    final step = widget.stepMinutes.clamp(1, 60);
    final slots = <String>[];
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += step) {
        final time24 = '${_pad(h)}:${_pad(m)}';
        if (use24) {
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

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _select(String time) {
    if (widget.value == null) {
      setState(() => _internal = time);
    }
    _controller.text = time;
    widget.onChanged?.call(time);
    _popoverController.hide();
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

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
          trailing: const AppInputIconSlot(icon: LucideIcons.clock),
          child: AppPressable(
            onTap: _interactive ? () => _popoverController.show() : null,
            enabled: _interactive,
            semanticLabel: widget.placeholder,
            mouseCursor: _interactive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: AbsorbPointer(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                enabled: !widget.disabled,
                style: context.typography.tabular(
                  appBareInputTextStyle(
                    context,
                    size: widget.size,
                    disabled: widget.disabled,
                    readOnly: widget.readOnly,
                  ),
                ),
                decoration: appBareInputDecoration(
                  context: context,
                  size: widget.size,
                  hintText: widget.placeholder,
                  disabled: widget.disabled,
                  readOnly: widget.readOnly,
                ),
              ),
            ),
          ),
        );
      },
      content: (context) {
        return AppPopoverListPanel(
          maxHeight: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final slot in _slots)
                AppPressable.builder(
                  onTap: () => _select(slot),
                  semanticLabel: slot,
                  borderRadius: AppRadii.mdAll,
                  builder: (context, states, _) {
                    final selected = slot == _currentValue;
                    final hovered = states.contains(WidgetState.hovered);
                    return AnimatedContainer(
                      duration: AppDurations.instant,
                      color: selected
                          ? colors.surfaceSelected
                          : hovered
                          ? colors.surfaceHover
                          : Colors.transparent,
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s2,
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        slot,
                        style: typography.tabular(
                          typography.body.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
