import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Semantic alert variants.
enum AppAlertVariant { primary, destructive }

/// Application alert wrapping [FAlert].
class AppAlert extends StatelessWidget {
  const AppAlert({required this.title, this.subtitle, this.icon, this.variant = AppAlertVariant.primary, super.key});

  final String title;
  final String? subtitle;
  final Widget? icon;
  final AppAlertVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FAlert(
      variant: variant == AppAlertVariant.destructive ? FAlertVariant.destructive : FAlertVariant.primary,
      icon: icon,
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
    );
  }
}

/// Application indeterminate linear progress wrapping [FProgress].
class AppLinearProgress extends StatelessWidget {
  const AppLinearProgress({this.semanticsLabel, super.key});

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => FProgress(semanticsLabel: semanticsLabel);
}

/// Application indeterminate circular progress wrapping [FCircularProgress].
class AppCircularProgress extends StatelessWidget {
  const AppCircularProgress({super.key});

  @override
  Widget build(BuildContext context) => const FCircularProgress();
}

/// Application determinate progress wrapping [FDeterminateProgress].
class AppDeterminateProgress extends StatelessWidget {
  const AppDeterminateProgress({required this.value, this.semanticsLabel, super.key});

  final double value;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return FDeterminateProgress(value: value.clamp(0, 1), semanticsLabel: semanticsLabel);
  }
}
