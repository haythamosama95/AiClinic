import 'package:flutter/material.dart';

/// Slides paginated content horizontally when [pageKey] changes.
///
/// Set [direction] to `1` for forward (next page) or `-1` for backward (previous).
/// Pass `0` to swap content instantly without animating.
class AppPaginatedSlideSwitcher extends StatefulWidget {
  const AppPaginatedSlideSwitcher({
    required this.pageKey,
    required this.direction,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.onAnimatingChanged,
    super.key,
  });

  final Object pageKey;
  final int direction;
  final Widget child;
  final Duration duration;
  final ValueChanged<bool>? onAnimatingChanged;

  static const curve = Curves.easeInOutCubic;

  @override
  State<AppPaginatedSlideSwitcher> createState() => _AppPaginatedSlideSwitcherState();
}

class _AppPaginatedSlideSwitcherState extends State<AppPaginatedSlideSwitcher> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<double>? _animation;
  Widget? _outgoingChild;
  var _outgoingDirection = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..addStatusListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(covariant AppPaginatedSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.pageKey != widget.pageKey && widget.direction != 0) {
      _outgoingChild = oldWidget.child;
      _outgoingDirection = widget.direction;
      _animation = CurvedAnimation(parent: _controller, curve: AppPaginatedSlideSwitcher.curve);
      _notifyAnimatingChanged(true);
      _controller.forward(from: 0);
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    setState(() {
      _outgoingChild = null;
      _outgoingDirection = 0;
    });
    _controller.reset();
    _notifyAnimatingChanged(false);
  }

  void _notifyAnimatingChanged(bool animating) {
    final callback = widget.onAnimatingChanged;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      callback(animating);
    });
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_outgoingChild == null) {
      return widget.child;
    }

    final animation = _animation!;
    final direction = _outgoingDirection.toDouble();

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          SlideTransition(
            position: Tween<Offset>(begin: Offset.zero, end: Offset(-direction, 0)).animate(animation),
            child: IgnorePointer(child: _outgoingChild!),
          ),
          SlideTransition(
            position: Tween<Offset>(begin: Offset(direction, 0), end: Offset.zero).animate(animation),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
