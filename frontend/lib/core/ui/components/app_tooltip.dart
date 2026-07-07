import 'package:flutter/material.dart';

/// Application-owned tooltip wrapper.
class AppTooltip extends StatelessWidget {
  const AppTooltip({required this.message, required this.child, this.preferBelow, super.key});

  final String message;
  final Widget child;

  /// When `false`, the tooltip prefers appearing above the trigger (web default `side="top"`).
  final bool? preferBelow;

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: message, preferBelow: preferBelow, child: child);
  }
}
