import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Optional prompt to save a custom visit-line name to the organization catalog.
class SaveToCatalogDialog extends StatelessWidget {
  const SaveToCatalogDialog({required this.normalizedName, required this.itemTypeLabel, super.key});

  final String normalizedName;
  final String itemTypeLabel;

  /// Returns `true` when the user accepts, `false` when declined, or `null` if dismissed.
  static Future<bool?> show(BuildContext context, {required String normalizedName, required String itemTypeLabel}) {
    return AppDialog.show<bool>(
      context: context,
      title: 'Save to catalog?',
      barrierDismissible: false,
      body: SaveToCatalogDialog(normalizedName: normalizedName, itemTypeLabel: itemTypeLabel),
      actions: [
        AppButton(
          label: 'Not now',
          variant: AppButtonVariant.outline,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(label: 'Save to catalog', expand: false, onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'Add "$normalizedName" to your organization $itemTypeLabel catalog so you can pick it faster next time?',
      style: theme.textTheme.bodyMedium,
    );
  }
}
