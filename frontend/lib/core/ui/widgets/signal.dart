import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/providers/reduced_motion_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Signature "Signal" primitive — active nav, command bar focus, AI thinking pulse.
enum SignalVariant { standard, ai }

enum SignalOrientation { horizontal, vertical }

enum SignalSize { default_, hero }

class Signal extends ConsumerStatefulWidget {
  const Signal({
    super.key,
    this.variant = SignalVariant.standard,
    this.orientation = SignalOrientation.horizontal,
    this.size = SignalSize.default_,
    this.thinking = false,
    this.active = true,
  });

  final SignalVariant variant;
  final SignalOrientation orientation;
  final SignalSize size;
  final bool thinking;
  final bool active;

  static const double thicknessDefault = 2;
  static const double thicknessHero = 3;

  @override
  ConsumerState<Signal> createState() => _SignalState();
}

class _SignalState extends ConsumerState<Signal>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupPulse();
  }

  @override
  void didUpdateWidget(Signal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking ||
        oldWidget.variant != widget.variant) {
      _setupPulse();
    }
  }

  void _setupPulse() {
    _pulseController?.dispose();
    _pulseController = null;
    _pulseAnimation = null;

    final reduced = ref.read(reducedMotionProvider);
    final shouldPulse =
        widget.thinking && widget.variant == SignalVariant.ai && !reduced;

    if (shouldPulse) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
      _pulseAnimation = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.0), weight: 50),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.5), weight: 50),
      ]).animate(_pulseController!);
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Color _signalColor(BuildContext context) {
    final colors = context.colors;
    return widget.variant == SignalVariant.ai
        ? colors.signalColorAi
        : colors.signalColor;
  }

  double get _thickness => widget.size == SignalSize.hero
      ? Signal.thicknessHero
      : Signal.thicknessDefault;

  List<BoxShadow>? _glow(Color color, {double intensity = 0.35}) {
    if (!widget.active) return null;
    final reduced = ref.watch(reducedMotionProvider);
    if (reduced) return null;
    return [
      BoxShadow(color: color.withValues(alpha: intensity), blurRadius: 8),
    ];
  }

  List<BoxShadow>? _thinkingGlow(Color color, double t) {
    final intensity = 0.45 * t;
    return [
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: 12 * t,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = _signalColor(context);
    final isHorizontal = widget.orientation == SignalOrientation.horizontal;
    final reduced = ref.watch(reducedMotionProvider);

    if (widget.thinking && widget.variant == SignalVariant.ai && !reduced) {
      return AnimatedBuilder(
        animation: _pulseAnimation!,
        builder: (context, _) {
          final t = _pulseAnimation!.value;
          return _buildBar(
            context,
            color: color.withValues(alpha: t.clamp(0.5, 1.0)),
            glow: _thinkingGlow(color, t),
            isHorizontal: isHorizontal,
          );
        },
      );
    }

    return _buildBar(
      context,
      color: color,
      glow: _glow(color),
      isHorizontal: isHorizontal,
    );
  }

  Widget _buildBar(
    BuildContext context, {
    required Color color,
    required List<BoxShadow>? glow,
    required bool isHorizontal,
  }) {
    return Container(
      width: isHorizontal ? double.infinity : _thickness,
      height: isHorizontal ? _thickness : double.infinity,
      constraints: BoxConstraints(
        minWidth: isHorizontal ? 0 : _thickness,
        minHeight: isHorizontal ? _thickness : 0,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9999),
        boxShadow: glow,
      ),
    );
  }
}
