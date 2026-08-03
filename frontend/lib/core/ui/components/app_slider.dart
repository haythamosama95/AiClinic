import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

typedef AppSliderValueFormatter = String Function(double value);

/// Application-owned slider (web `Slider`).
///
/// Custom track + thumb (no Material [Slider]) to avoid [OverlayPortal] layout
/// failures inside scroll views. 6px track, 20px thumb, optional value label.
class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    this.value,
    this.valueDouble,
    this.defaultValue,
    this.defaultValueDouble,
    this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.disabled = false,
    this.invalid = false,
    this.showValue = true,
    this.formatValue,
    this.id,
    this.ariaLabelledBy,
  }) : assert(value == null || valueDouble == null),
       assert(defaultValue == null || defaultValueDouble == null);

  /// Controlled value list (single-thumb uses index `0`).
  final List<double>? value;

  /// Controlled single value (mutually exclusive with [value]).
  final double? valueDouble;

  /// Uncontrolled default list. Falls back to `[50]` when omitted.
  final List<double>? defaultValue;

  /// Uncontrolled single default (mutually exclusive with [defaultValue]).
  final double? defaultValueDouble;

  final ValueChanged<List<double>>? onChanged;
  final double min;
  final double max;
  final double step;
  final bool disabled;
  final bool invalid;
  final bool showValue;
  final AppSliderValueFormatter? formatValue;
  final String? id;
  final String? ariaLabelledBy;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  static const _trackHeight = 6.0;
  static const _thumbRadius = 10.0;
  static const _touchHeight = 48.0;

  late double _internalValue;
  final _focusNode = FocusNode();
  var _focused = false;
  var _pressed = false;
  var _hovered = false;

  bool get _isControlled => _controlledList != null;

  bool get _interactive => !widget.disabled && (!_isControlled || widget.onChanged != null);

  List<double>? get _controlledList {
    if (widget.value != null) return widget.value;
    if (widget.valueDouble != null) return [widget.valueDouble!];
    return null;
  }

  List<double> get _defaultList {
    if (widget.defaultValue != null) return widget.defaultValue!;
    if (widget.defaultValueDouble != null) return [widget.defaultValueDouble!];
    return const [50];
  }

  double get _effectiveValue => _controlledList?.first ?? _internalValue;

  @override
  void initState() {
    super.initState();
    _internalValue = _defaultList.first;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled && _defaultList != _resolveDefaultList(oldWidget)) {
      _internalValue = _defaultList.first;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  List<double> _resolveDefaultList(AppSlider source) {
    if (source.defaultValue != null) return source.defaultValue!;
    if (source.defaultValueDouble != null) return [source.defaultValueDouble!];
    return const [50];
  }

  String _formatValue(double value) {
    return widget.formatValue?.call(value) ?? '$value%';
  }

  double _clampAndSnap(double raw) {
    final clamped = raw.clamp(widget.min, widget.max);
    if (widget.step <= 0) return clamped;
    final steps = ((clamped - widget.min) / widget.step).round();
    return (widget.min + steps * widget.step).clamp(widget.min, widget.max);
  }

  double _fractionFor(double value) {
    if (widget.max <= widget.min) return 0;
    return ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _commitValue(double next) {
    if (!_interactive) return;
    final snapped = _clampAndSnap(next);
    if (!_isControlled) {
      setState(() => _internalValue = snapped);
    }
    widget.onChanged?.call([snapped]);
  }

  void _updateFromLocalDx(double localDx, double trackWidth) {
    final usable = trackWidth - _thumbRadius * 2;
    if (usable <= 0) return;
    final fraction = ((localDx - _thumbRadius) / usable).clamp(0.0, 1.0);
    _commitValue(widget.min + fraction * (widget.max - widget.min));
  }

  void _nudgeByStep(int direction) {
    if (!_interactive) return;
    final delta = widget.step > 0 ? widget.step * direction : (widget.max - widget.min) * 0.01 * direction;
    _commitValue(_effectiveValue + delta);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_interactive || event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowDown) {
      _nudgeByStep(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowUp) {
      _nudgeByStep(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _commitValue(widget.min);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _commitValue(widget.max);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildControl(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final focusRing = widget.invalid ? appInputInvalidFocusRingColor(colors) : appInputFocusRingColor(context);
    final current = _clampAndSnap(_effectiveValue);
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final thumbScale = _pressed && _interactive && !reducedMotion
        ? 0.95
        : (_hovered && _interactive && !reducedMotion ? 1.05 : 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbCenterX = _thumbRadius + _fractionFor(current) * (trackWidth - _thumbRadius * 2);
        final activeWidth = thumbCenterX + _thumbRadius;

        return Semantics(
          slider: true,
          enabled: !widget.disabled,
          identifier: widget.id,
          label: widget.ariaLabelledBy,
          value: _formatValue(current),
          increasedValue: _formatValue(_clampAndSnap(current + (widget.step > 0 ? widget.step : 1))),
          decreasedValue: _formatValue(_clampAndSnap(current - (widget.step > 0 ? widget.step : 1))),
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: _interactive,
            onKeyEvent: _handleKeyEvent,
            child: MouseRegion(
              cursor: _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
              onEnter: _interactive ? (_) => setState(() => _hovered = true) : null,
              onExit: (_) => setState(() {
                _hovered = false;
                _pressed = false;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _interactive
                    ? (details) {
                        setState(() => _pressed = true);
                        _updateFromLocalDx(details.localPosition.dx, trackWidth);
                      }
                    : null,
                onTapUp: _interactive ? (_) => setState(() => _pressed = false) : null,
                onTapCancel: _interactive ? () => setState(() => _pressed = false) : null,
                onHorizontalDragStart: _interactive
                    ? (details) {
                        setState(() => _pressed = true);
                        _updateFromLocalDx(details.localPosition.dx, trackWidth);
                      }
                    : null,
                onHorizontalDragUpdate: _interactive
                    ? (details) => _updateFromLocalDx(details.localPosition.dx, trackWidth)
                    : null,
                onHorizontalDragEnd: _interactive ? (_) => setState(() => _pressed = false) : null,
                child: SizedBox(
                  height: _touchHeight,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: _trackHeight,
                          width: trackWidth,
                          decoration: BoxDecoration(
                            color: widget.disabled ? colors.surfaceMuted.withValues(alpha: 0.5) : colors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: _trackHeight,
                          width: activeWidth.clamp(0.0, trackWidth),
                          decoration: BoxDecoration(
                            color: widget.disabled ? colors.actionPrimary.withValues(alpha: 0.5) : colors.actionPrimary,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumbCenterX - _thumbRadius,
                        top: (_touchHeight - _thumbRadius * 2) / 2,
                        child: AnimatedScale(
                          scale: thumbScale,
                          duration: AppMotion.fast,
                          curve: AppMotion.standardCurve,
                          child: _SliderThumb(
                            colors: colors,
                            elevation: elevation,
                            invalid: widget.invalid,
                            focused: _focused,
                            focusRing: focusRing,
                            disabled: widget.disabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final current = _clampAndSnap(_effectiveValue);

    return Opacity(
      opacity: widget.disabled ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showValue) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _formatValue(current),
                style: AppTypography.bodyStrong(
                  context,
                ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
          ],
          _buildControl(context),
        ],
      ),
    );
  }
}

class _SliderThumb extends StatelessWidget {
  const _SliderThumb({
    required this.colors,
    required this.elevation,
    required this.invalid,
    required this.focused,
    required this.focusRing,
    required this.disabled,
  });

  final AppSemanticColors colors;
  final AppElevation elevation;
  final bool invalid;
  final bool focused;
  final Color focusRing;
  final bool disabled;

  static const _diameter = _AppSliderState._thumbRadius * 2;

  @override
  Widget build(BuildContext context) {
    final borderColor = invalid ? colors.statusDangerBorder : colors.borderDefault;

    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceDefault,
        border: Border.all(color: borderColor),
        boxShadow: [
          ...elevation.shadows1,
          if (focused && !disabled) BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2),
        ],
      ),
    );
  }
}
