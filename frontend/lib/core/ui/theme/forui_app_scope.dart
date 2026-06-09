import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_theme_meta.dart';
import 'forui_theme.dart';
import 'variants/app_theme_variant.dart';

/// Provides [FTheme], toasts, and tooltips for the entire widget tree.
///
/// Place via [MaterialApp.builder] so forui stays isolated in `core/ui`.
class ForuiAppScope extends StatelessWidget {
  const ForuiAppScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final variant = Theme.of(context).extension<AppThemeMeta>()?.variant ?? AppThemeVariant.clinic;

    return FTheme(
      data: ForuiTheme.dataFor(brightness, variant: variant),
      child: FToaster(child: FTooltipGroup(child: child)),
    );
  }
}
