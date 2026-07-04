import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

/// Wraps an action control with a tooltip when [disabledReason] is set.
class BillingActionButton extends StatelessWidget {
  const BillingActionButton({
    required this.child,
    this.disabledReason,
    super.key,
  });

  final Widget child;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    if (disabledReason != null) {
      return AppTooltip(message: disabledReason!, child: child);
    }
    return child;
  }
}
