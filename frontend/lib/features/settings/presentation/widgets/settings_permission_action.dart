import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

/// Wraps an action with a [AppTooltip] when [disabledReason] is set (RBAC UX).
class SettingsPermissionAction extends StatelessWidget {
  const SettingsPermissionAction({
    required this.disabledReason,
    required this.builder,
    super.key,
  });

  final String? disabledReason;
  final Widget Function(bool enabled) builder;

  @override
  Widget build(BuildContext context) {
    final enabled = disabledReason == null;
    final child = builder(enabled);
    if (enabled) {
      return child;
    }
    return AppTooltip(
      message: disabledReason!,
      child: AbsorbPointer(child: Opacity(opacity: 0.55, child: child)),
    );
  }
}
