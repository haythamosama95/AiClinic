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
  late int _requestedIndex;
  var _isTransitioning = false;

  static const _curve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _visibleIndex = widget.index;
    _requestedIndex = widget.index;
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
    if (widget.index != _requestedIndex) {
      _requestedIndex = widget.index;
      _scheduleTransitionToRequested();
    }
  }

  void _scheduleTransitionToRequested() {
    if (_isTransitioning || _visibleIndex == _requestedIndex) {
      return;
    }
    _runTransition(_requestedIndex);
  }

  Future<void> _runTransition(int targetIndex) async {
    setState(() => _isTransitioning = true);

    await _controller.reverse();
    if (!mounted) {
      return;
    }

    if (_requestedIndex != targetIndex) {
      setState(() => _isTransitioning = false);
      _scheduleTransitionToRequested();
      return;
    }

    setState(() => _visibleIndex = targetIndex);

    await _controller.forward();
    if (!mounted) {
      return;
    }

    setState(() => _isTransitioning = false);

    if (_visibleIndex != _requestedIndex) {
      _scheduleTransitionToRequested();
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
