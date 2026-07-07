import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/motion/app_page_transition.dart';

typedef ShellPageTransitionBuilder = Widget Function(BuildContext context, Widget child, Object activePageKey);

/// Shell content host with wait-mode page transitions (web `AnimatePresence` + `PageTransition`).
class ShellPageTransition extends StatefulWidget {
  const ShellPageTransition({required this.pageKey, required this.child, required this.builder, super.key});

  final Object pageKey;
  final Widget child;
  final ShellPageTransitionBuilder builder;

  @override
  State<ShellPageTransition> createState() => _ShellPageTransitionState();
}

enum _TransitionPhase { idle, exiting, entering }

class _ShellPageTransitionState extends State<ShellPageTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  late Object _shownKey;
  late Widget _shownChild;

  Widget? _outgoingChild;
  Object? _pendingKey;
  Widget? _pendingChild;
  _TransitionPhase _phase = _TransitionPhase.idle;

  @override
  void initState() {
    super.initState();
    _shownKey = widget.pageKey;
    _shownChild = _keyedChild(widget.pageKey, widget.child);
    _controller = AnimationController(vsync: this, duration: AppPageTransitionMotion.duration)..value = 1;
    _curve = CurvedAnimation(parent: _controller, curve: AppPageTransitionMotion.curve);
  }

  @override
  void didUpdateWidget(ShellPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageKey == _shownKey && _phase == _TransitionPhase.idle) {
      if (widget.child != oldWidget.child) {
        setState(() => _shownChild = _keyedChild(widget.pageKey, widget.child));
      }
      return;
    }

    if (widget.pageKey == _shownKey) {
      return;
    }

    _pendingKey = widget.pageKey;
    _pendingChild = widget.child;
    _scheduleTransition();
  }

  void _scheduleTransition() {
    if (_phase != _TransitionPhase.idle) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _TransitionPhase.idle || _pendingKey == null) {
        return;
      }
      _runTransition();
    });
  }

  Future<void> _runTransition() async {
    final incomingKey = _pendingKey;
    final incomingChild = _pendingChild;
    if (incomingKey == null || incomingChild == null || incomingKey == _shownKey) {
      _pendingKey = null;
      _pendingChild = null;
      return;
    }

    _pendingKey = null;
    _pendingChild = null;

    if (AppMotion.prefersReducedMotion(context)) {
      setState(() {
        _shownKey = incomingKey;
        _shownChild = _keyedChild(incomingKey, incomingChild);
        _outgoingChild = null;
        _phase = _TransitionPhase.idle;
        _controller.value = 1;
      });
      _maybeRunPending();
      return;
    }

    final outgoingChild = _shownChild;

    setState(() {
      _phase = _TransitionPhase.exiting;
      _outgoingChild = outgoingChild;
      _controller.value = 1;
    });

    await _controller.reverse(from: 1);
    if (!mounted) {
      return;
    }

    setState(() {
      _outgoingChild = null;
      _shownKey = incomingKey;
      _shownChild = _keyedChild(incomingKey, incomingChild);
      _phase = _TransitionPhase.entering;
      _controller.value = 0;
    });

    await _controller.forward(from: 0);
    if (!mounted) {
      return;
    }

    setState(() => _phase = _TransitionPhase.idle);
    _maybeRunPending();
  }

  void _maybeRunPending() {
    if (_pendingKey != null && _pendingKey != _shownKey) {
      _scheduleTransition();
    }
  }

  static Widget _keyedChild(Object key, Widget child) {
    return KeyedSubtree(key: ValueKey(key), child: child);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.prefersReducedMotion(context)) {
      return widget.builder(context, _keyedChild(widget.pageKey, widget.child), widget.pageKey);
    }

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final progress = _controller.value;
        final Widget page = switch (_phase) {
          _TransitionPhase.exiting => _buildOutgoing(progress),
          _TransitionPhase.entering => _buildIncoming(progress),
          _TransitionPhase.idle => _shownChild,
        };

        return widget.builder(context, page, _shownKey);
      },
    );
  }

  Widget _buildOutgoing(double progress) {
    final outgoing = _outgoingChild;
    if (outgoing == null) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: AppPageTransitionMotion.build(progress: progress, exiting: true, child: outgoing),
    );
  }

  Widget _buildIncoming(double progress) {
    return AppPageTransitionMotion.build(progress: progress, exiting: false, child: _shownChild);
  }
}
