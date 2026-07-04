import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_calendar_shared.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Inclusive date range value.
class AppDateRange {
  const AppDateRange({
    this.start,
    this.end,
  });

  final DateTime? start;
  final DateTime? end;

  AppDateRange copyWith({
    DateTime? start,
    DateTime? end,
  }) {
    return AppDateRange(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

/// Preset shortcut for [AppDateRangePicker].
class AppDateRangePreset {
  const AppDateRangePreset({
    required this.label,
    required this.range,
  });

  final String label;
  final AppDateRange range;
}

/// Dual-month range picker with presets and inclusive-range messaging.
class AppDateRangePicker extends StatefulWidget {
  const AppDateRangePicker({
    this.value,
    this.defaultValue,
    this.onChanged,
    this.presets,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Select date range',
    this.focusNode,
    super.key,
  });

  final AppDateRange? value;
  final AppDateRange? defaultValue;
  final ValueChanged<AppDateRange>? onChanged;
  final List<AppDateRangePreset>? presets;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final FocusNode? focusNode;

  @override
  State<AppDateRangePicker> createState() => _AppDateRangePickerState();
}

class _AppDateRangePickerState extends State<AppDateRangePicker> {
  late AppPopoverController _popoverController;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  AppDateRange _internal = const AppDateRange();
  late DateTime _leftMonth;

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _internal = widget.defaultValue ?? const AppDateRange();
    _leftMonth = _range.start ?? DateTime.now();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }

  AppDateRange get _range => widget.value ?? _internal;

  List<AppDateRangePreset> get _presets =>
      widget.presets ?? _defaultPresets();

  String _formatRange(BuildContext context) {
    final range = _range;
    if (range.start == null && range.end == null) return '';
    if (range.start != null && range.end == null) {
      return appCalendarFormatShortDate(context, range.start!);
    }
    if (range.start != null && range.end != null) {
      return '${appCalendarFormatShortDate(context, range.start!)} – '
          '${appCalendarFormatShortDate(context, range.end!)}';
    }
    return '';
  }

  String? _inclusiveMessage(BuildContext context) {
    final range = _range;
    if (range.start != null && range.end != null) {
      return 'Inclusive range: ${_formatRange(context)}';
    }
    if (range.start != null) return 'Select end date';
    return null;
  }

  void _applyRange(AppDateRange next, {bool close = false}) {
    if (widget.value == null) {
      setState(() => _internal = next);
    }
    widget.onChanged?.call(next);
    if (close) _popoverController.hide();
    setState(() {});
  }

  void _handleDaySelected(DateTime day) {
    final normalized = appCalendarStartOfDay(day);
    final range = _range;
    AppDateRange next;
    if (range.start == null || (range.start != null && range.end != null)) {
      next = AppDateRange(start: normalized, end: null);
    } else if (normalized.isBefore(appCalendarStartOfDay(range.start!))) {
      next = AppDateRange(start: normalized, end: range.start);
    } else {
      next = AppDateRange(start: range.start, end: normalized);
    }
    _applyRange(next, close: next.start != null && next.end != null);
  }

  void _shiftMonths(int delta) {
    setState(() {
      _leftMonth = DateTime(_leftMonth.year, _leftMonth.month + delta, 1);
    });
  }

  DateTime get _rightMonth =>
      DateTime(_leftMonth.year, _leftMonth.month + 1, 1);

  @override
  Widget build(BuildContext context) {
    final display = _formatRange(context);
    final message = _inclusiveMessage(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final firstMonth = isRtl ? _rightMonth : _leftMonth;
    final secondMonth = isRtl ? _leftMonth : _rightMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPopover(
          controller: _popoverController,
          placement: AppPopoverPlacement.bottomStart,
          onOpenChange: (_) => setState(() {}),
          trigger: (context, show, hide, toggle) {
            return AppInputFrame(
              focusNode: _focusNode,
              size: widget.size,
              invalid: widget.invalid,
              disabled: widget.disabled,
              trailing: const AppInputIconSlot(icon: LucideIcons.calendar),
              child: AppPressable(
                onTap: widget.disabled ? null : () => _popoverController.show(),
                enabled: !widget.disabled,
                semanticLabel: widget.placeholder,
                mouseCursor: widget.disabled
                    ? SystemMouseCursors.forbidden
                    : SystemMouseCursors.click,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    display.isEmpty ? widget.placeholder : display,
                    style: appBareInputTextStyle(
                      context,
                      size: widget.size,
                      disabled: widget.disabled,
                    ).copyWith(
                      color: display.isEmpty
                          ? context.colors.textPlaceholder
                          : context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          },
          content: (context) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
                    children: [
                      for (final preset in _presets)
                        _PresetChip(
                          label: preset.label,
                          onTap: () => _applyRange(preset.range, close: true),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 480;
                      final children = [
                        AppCalendarGrid(
                          month: firstMonth,
                          rangeStart: _range.start,
                          rangeEnd: _range.end,
                          onDaySelected: _handleDaySelected,
                          showHeader: true,
                          compact: true,
                          onPreviousMonth: null,
                          onNextMonth: null,
                        ),
                        AppCalendarGrid(
                          month: secondMonth,
                          rangeStart: _range.start,
                          rangeEnd: _range.end,
                          onDaySelected: _handleDaySelected,
                          showHeader: true,
                          compact: true,
                          onPreviousMonth: null,
                          onNextMonth: null,
                        ),
                      ];
                      if (stacked) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              if (i > 0) const SizedBox(height: AppSpacing.s4),
                              children[i],
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: children[0]),
                          const SizedBox(width: AppSpacing.s4),
                          Expanded(child: children[1]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavLink(
                        label: 'Previous',
                        onTap: () => _shiftMonths(-1),
                      ),
                      _NavLink(
                        label: 'Next',
                        onTap: () => _shiftMonths(1),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: context.typography.caption.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

List<AppDateRangePreset> _defaultPresets() {
  final today = appCalendarStartOfDay(DateTime.now());
  final weekStart = today.subtract(Duration(days: today.weekday % 7));
  final weekEnd = weekStart.add(const Duration(days: 6));
  final monthStart = DateTime(today.year, today.month, 1);
  final monthEnd = DateTime(today.year, today.month + 1, 0);
  return [
    AppDateRangePreset(
      label: 'Today',
      range: AppDateRange(start: today, end: today),
    ),
    AppDateRangePreset(
      label: 'This week',
      range: AppDateRange(start: weekStart, end: weekEnd),
    ),
    AppDateRangePreset(
      label: 'This month',
      range: AppDateRange(start: monthStart, end: monthEnd),
    ),
  ];
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppPressable.builder(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: AppDurations.instant,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s1 + AppSpacing.s0_5,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderDefault),
            borderRadius: AppRadii.mdAll,
            color: hovered ? colors.surfaceHover : Colors.transparent,
          ),
          child: Text(
            label,
            style: typography.bodySm.copyWith(color: colors.textPrimary),
          ),
        );
      },
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Text(
        label,
        style: context.typography.caption.copyWith(
          color: context.colors.textLink,
        ),
      ),
    );
  }
}
