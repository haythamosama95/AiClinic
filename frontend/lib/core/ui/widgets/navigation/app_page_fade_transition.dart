import 'package:flutter/material.dart';

/// Fades the outgoing page out, swaps content, then fades the incoming page in.
class AppPageFadeTransition extends StatefulWidget {
  const AppPageFadeTransition({
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
    super.key,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<AppPageFadeTransition> createState() => _AppPageFadeTransitionState();
}

class _AppPageFadeTransitionState extends State<AppPageFadeTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late int _visibleIndex;
  int? _queuedIndex;
  var _isTransitioning = false;

  static const _curve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _visibleIndex = widget.index;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: _curve);
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppPageFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != _visibleIndex && widget.index != _queuedIndex) {
      _queueTransition(widget.index);
    }
  }

  void _queueTransition(int targetIndex) {
    if (_isTransitioning) {
      _queuedIndex = targetIndex;
      return;
    }
    _runTransition(targetIndex);
  }

  Future<void> _runTransition(int targetIndex) async {
    _isTransitioning = true;
    _queuedIndex = null;

    await _controller.reverse();
    if (!mounted) {
      return;
    }

    setState(() => _visibleIndex = targetIndex);

    await _controller.forward();
    if (!mounted) {
      return;
    }

    _isTransitioning = false;

    final queued = _queuedIndex;
    if (queued != null && queued != _visibleIndex) {
      _queueTransition(queued);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: const Key('app_page_fade_transition'),
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _opacity,
          child: IgnorePointer(ignoring: _isTransitioning, child: child),
        );
      },
      child: IndexedStack(index: _visibleIndex, children: widget.children),
    );
  }
}
