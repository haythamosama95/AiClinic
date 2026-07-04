import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Single-value slider with optional formatted output.
class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    this.id,
    this.value,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.disabled = false,
    this.invalid = false,
    this.showValue = true,
    this.formatValue,
    this.onChanged,
  });

  final String? id;
  final double? value;
  final double min;
  final double max;
  final double step;
  final bool disabled;
  final bool invalid;
  final bool showValue;
  final String Function(double value)? formatValue;
  final ValueChanged<double>? onChanged;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  late double _localValue;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value ?? (widget.max - widget.min) / 2 + widget.min;
  }

  @override
  void didUpdateWidget(AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      _localValue = widget.value!;
    }
  }

  double get _current => widget.value ?? _localValue;

  String _format(double v) => widget.formatValue?.call(v) ?? '${v.round()}%';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showValue)
          Semantics(
            liveRegion: true,
            child: Text(
              _format(_current),
              style: typography.bodyStrong.copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (widget.showValue) const SizedBox(height: AppSpacing.s2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: colors.actionPrimary,
            inactiveTrackColor: colors.surfaceMuted,
            thumbColor: colors.surfaceDefault,
            overlayColor: colors.focusRing,
            disabledActiveTrackColor: colors.actionDisabledBg,
            disabledInactiveTrackColor: colors.surfaceMuted,
            disabledThumbColor: colors.surfaceDefault,
            thumbShape: _AppSliderThumbShape(
              invalid: widget.invalid,
              colors: colors,
              elevation: context.elevation.level1,
            ),
          ),
          child: Slider(
            value: _current.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.step > 0
                ? ((widget.max - widget.min) / widget.step).round()
                : null,
            onChanged: widget.disabled
                ? null
                : (v) {
                    setState(() => _localValue = v);
                    widget.onChanged?.call(v);
                  },
          ),
        ),
      ],
    );
  }
}

class _AppSliderThumbShape extends SliderComponentShape {
  const _AppSliderThumbShape({
    required this.invalid,
    required this.colors,
    required this.elevation,
  });

  final bool invalid;
  final AppColors colors;
  final List<BoxShadow> elevation;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(20, 20);
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
    final scale = 1.0 + (activationAnimation.value * 0.05);
    final radius = 10.0 * scale;

    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? colors.surfaceDefault
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()
      ..color = invalid ? colors.statusDangerBorder : colors.borderDefault
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }
}
