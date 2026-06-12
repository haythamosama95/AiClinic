import 'package:flutter/material.dart';

/// Fades content in and out while smoothly animating layout height.
class AppFadeInOutPanel extends StatefulWidget {
  const AppFadeInOutPanel({
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.animateOnMount = false,
    this.onHidden,
    super.key,
  });

  final bool visible;
  final Widget child;
  final Duration duration;
  final bool animateOnMount;
  final VoidCallback? onHidden;

  @override
  State<AppFadeInOutPanel> createState() => _AppFadeInOutPanelState();
}

class _AppFadeInOutPanelState extends State<AppFadeInOutPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  var _showContent = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (widget.visible) {
      _showContent = true;
      if (widget.animateOnMount) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AppFadeInOutPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.visible && !oldWidget.visible) {
      setState(() => _showContent = true);
      _controller.forward(from: 0);
    } else if (!widget.visible && oldWidget.visible) {
      _controller.reverse().then((_) {
        if (mounted && !widget.visible) {
          setState(() => _showContent = false);
          widget.onHidden?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: widget.duration,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: _showContent
          ? FadeTransition(
              opacity: _opacity,
              child: IgnorePointer(
                ignoring: !widget.visible,
                child: Semantics(hidden: !widget.visible, child: widget.child),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
