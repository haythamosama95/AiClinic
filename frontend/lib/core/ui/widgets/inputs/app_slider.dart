import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Slider for selecting a numeric value within a range.
///
/// Uses a token-styled [Slider] for native keyboard and pointer behavior.
class AppSlider extends StatefulWidget {
  const AppSlider({
    this.value,
    this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.disabled = false,
    this.invalid = false,
    this.showValue = true,
    this.formatValue,
    this.semanticLabel,
    super.key,
  });

  final double? value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final double step;
  final bool disabled;
  final bool invalid;
  final bool showValue;
  final String Function(double value)? formatValue;
  final String? semanticLabel;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  late double _internalValue;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.value ?? (widget.max - widget.min) / 2 + widget.min;
  }

  @override
  void didUpdateWidget(covariant AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      _internalValue = widget.value!;
    }
  }

  double get _current => widget.value ?? _internalValue;

  String _format(double value) =>
      widget.formatValue?.call(value) ?? '${value.round()}%';

  void _handleChanged(double next) {
    if (widget.disabled) return;
    if (widget.value == null) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.disabled) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _handleChanged((_current + widget.step).clamp(widget.min, widget.max));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _handleChanged((_current - widget.step).clamp(widget.min, widget.max));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final duration = AppMotion.reduced(context)
        ? AppDurations.instant
        : AppDurations.fast;

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: AppSpacing.s1 + AppSpacing.s0_5,
      activeTrackColor: colors.actionPrimary,
      inactiveTrackColor: colors.surfaceMuted,
      thumbColor: colors.surfaceDefault,
      overlayColor: colors.focusRing.withValues(alpha: 0.12),
      disabledActiveTrackColor: colors.actionPrimary.withValues(alpha: 0.5),
      disabledInactiveTrackColor: colors.surfaceMuted.withValues(alpha: 0.5),
      disabledThumbColor: colors.surfaceDefault.withValues(alpha: 0.5),
      thumbShape: _AppSliderThumbShape(
        borderColor: widget.invalid
            ? colors.statusDangerBorder
            : colors.borderDefault,
        elevation: AppShadows.forContext(context, 1),
        duration: duration,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: AppSpacing.s4),
      trackShape: const RoundedRectSliderTrackShape(),
    );

    return Semantics(
      label: widget.semanticLabel,
      slider: true,
      value: _current.toString(),
      increasedValue: (_current + widget.step).clamp(widget.min, widget.max).toString(),
      decreasedValue: (_current - widget.step).clamp(widget.min, widget.max).toString(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showValue)
            Semantics(
              liveRegion: true,
              child: Text(
                _format(_current),
                style: typography.tabular(
                  typography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          if (widget.showValue) const SizedBox(height: AppSpacing.s2),
          Focus(
            onKeyEvent: _handleKeyEvent,
            child: SliderTheme(
              data: sliderTheme,
              child: Slider(
                value: _current.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                divisions: widget.step > 0
                    ? ((widget.max - widget.min) / widget.step).round()
                    : null,
                onChanged: widget.disabled ? null : _handleChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSliderThumbShape extends SliderComponentShape {
  const _AppSliderThumbShape({
    required this.borderColor,
    required this.elevation,
    required this.duration,
  });

  final Color borderColor;
  final List<BoxShadow> elevation;
  final Duration duration;

  static const double _thumbRadius = AppSpacing.s2 + AppSpacing.s0_5;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size.fromRadius(_thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final scale = 1 + (activationAnimation.value * 0.05);
  final radius = _thumbRadius * (isDiscrete ? 1 : scale);

    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppSpacing.sPx;

    canvas.drawCircle(center, radius, borderPaint);

    for (final shadow in elevation) {
      canvas.drawCircle(
        center + shadow.offset,
        radius,
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurRadius),
      );
    }
  }
}
