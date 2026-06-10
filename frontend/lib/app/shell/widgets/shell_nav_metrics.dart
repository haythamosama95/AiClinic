import 'package:flutter/material.dart';

/// Collapse animation progress for shell nav descendants.
///
/// [collapseT] is `0` when fully expanded and `1` when fully collapsed.
class ShellNavMetrics extends InheritedWidget {
  const ShellNavMetrics({required this.collapseT, required super.child, super.key});

  final double collapseT;

  static ShellNavMetrics? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellNavMetrics>();
  }

  @override
  bool updateShouldNotify(covariant ShellNavMetrics oldWidget) {
    return oldWidget.collapseT != collapseT;
  }
}
