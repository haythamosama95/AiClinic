import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'forui_theme.dart';

/// Provides [FTheme], toasts, and tooltips for the entire widget tree.
///
/// Place via [MaterialApp.builder] so forui stays isolated in `core/ui`.
class ForuiAppScope extends StatelessWidget {
  const ForuiAppScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return FTheme(
      data: ForuiTheme.dataFor(brightness),
      child: FToaster(child: FTooltipGroup(child: child)),
    );
  }
}
