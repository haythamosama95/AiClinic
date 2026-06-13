import 'dart:async';

import 'package:flutter/material.dart';

/// Shows [placeholder] immediately and only reveals [loading] after [delay].
///
/// Avoids a brief full-screen spinner flash when [isLoading] resolves quickly.
class AppDeferredLoading extends StatefulWidget {
  const AppDeferredLoading({
    required this.isLoading,
    required this.placeholder,
    required this.loading,
    this.delay = const Duration(milliseconds: 250),
    super.key,
  });

  final bool isLoading;
  final Widget placeholder;
  final Widget loading;
  final Duration delay;

  @override
  State<AppDeferredLoading> createState() => _AppDeferredLoadingState();
}

class _AppDeferredLoadingState extends State<AppDeferredLoading> {
  Timer? _timer;
  var _showLoading = false;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant AppDeferredLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLoading) {
      _cancelTimer();
      if (_showLoading) {
        setState(() => _showLoading = false);
      }
      return;
    }

    if (!oldWidget.isLoading) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  void _scheduleReveal() {
    if (!widget.isLoading || _showLoading) {
      return;
    }

    _cancelTimer();
    _timer = Timer(widget.delay, () {
      if (!mounted || !widget.isLoading) {
        return;
      }
      setState(() => _showLoading = true);
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.placeholder;
    }

    return _showLoading ? widget.loading : widget.placeholder;
  }
}
