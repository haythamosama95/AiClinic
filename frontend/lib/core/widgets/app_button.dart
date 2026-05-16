import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Shared action button variants for consistent interaction patterns.
enum AppButtonVariant { primary, secondary, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(onPressed: isLoading ? null : onPressed, child: child),
      AppButtonVariant.secondary => OutlinedButton(onPressed: isLoading ? null : onPressed, child: child),
      AppButtonVariant.danger => FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
        child: child,
      ),
    };
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (icon == null) {
      return Text(label);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}
