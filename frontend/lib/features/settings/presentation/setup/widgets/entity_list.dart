import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Generic card-per-item list with add/remove (web `EntityList`).
class EntityList<T> extends StatelessWidget {
  const EntityList({
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.addLabel,
    required this.renderItem,
    required this.itemId,
    this.getItemLabel,
    this.minItems = 1,
    super.key,
  });

  final List<T> items;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final String addLabel;
  final int minItems;
  final Widget Function(T item, int index) renderItem;
  final String Function(T item, int index)? getItemLabel;
  final String Function(T item) itemId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space4),
          AppCard(
            key: ValueKey(itemId(items[index])),
            variant: CardVariant.flat,
            padding: CardPadding.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        getItemLabel?.call(items[index], index) ?? 'Item ${index + 1}',
                        style: AppTypography.bodyStrong(context),
                      ),
                    ),
                    if (items.length > minItems)
                      AppIconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: 'Remove',
                        variant: AppIconButtonVariant.ghost,
                        size: AppIconButtonSize.sm,
                        onPressed: () => onRemove(itemId(items[index])),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space4),
                renderItem(items[index], index),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space4),
        AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: onAdd,
          leadingIcon: const Icon(Icons.add, size: 16),
          child: Text(addLabel),
        ),
      ],
    );
  }
}
