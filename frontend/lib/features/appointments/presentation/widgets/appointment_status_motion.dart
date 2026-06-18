import 'package:flutter/material.dart';

/// Shared motion tokens for appointment status transitions.
abstract final class AppointmentStatusMotion {
  static const curve = Curves.easeOut;
  static const duration = Duration(milliseconds: 220);

  static Duration durationOf(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}

/// Animates [color] changes for status-tinted icons and accents.
class AnimatedAppointmentStatusColor extends StatefulWidget {
  const AnimatedAppointmentStatusColor({required this.color, required this.builder, super.key});

  final Color color;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  State<AnimatedAppointmentStatusColor> createState() => _AnimatedAppointmentStatusColorState();
}

class _AnimatedAppointmentStatusColorState extends State<AnimatedAppointmentStatusColor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _colorAnimation;
  late Color _displayColor;

  @override
  void initState() {
    super.initState();
    _displayColor = widget.color;
    _controller = AnimationController(vsync: this, duration: AppointmentStatusMotion.duration);
    _colorAnimation = AlwaysStoppedAnimation(widget.color);
  }

  @override
  void didUpdateWidget(covariant AnimatedAppointmentStatusColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color == widget.color) {
      return;
    }

    final motionDuration = AppointmentStatusMotion.durationOf(context);
    _controller.duration = motionDuration;
    if (motionDuration == Duration.zero) {
      setState(() => _displayColor = widget.color);
      _colorAnimation = AlwaysStoppedAnimation(widget.color);
      return;
    }

    _colorAnimation = ColorTween(
      begin: _displayColor,
      end: widget.color,
    ).animate(CurvedAnimation(parent: _controller, curve: AppointmentStatusMotion.curve));
    _controller.forward(from: 0).then((_) {
      if (mounted) {
        setState(() => _displayColor = widget.color);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppointmentStatusMotion.durationOf(context) == Duration.zero) {
      return widget.builder(context, widget.color);
    }

    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, _) => widget.builder(context, _colorAnimation.value ?? widget.color),
    );
  }
}
