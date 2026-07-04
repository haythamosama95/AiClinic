import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

/// Preview controls for locale and direction (web `DevLocaleControls` subset).
class DevLocaleControls extends ConsumerWidget {
  const DevLocaleControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final preview = ref.watch(devPreviewProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderDefault),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space3,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate, size: 16, color: colors.iconMuted),
                const SizedBox(width: AppSpacing.space2),
                Text('Preview theming', style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
              ],
            ),
            _DevSegmentedControl<TextDirection>(
              label: 'Text direction',
              value: preview.direction,
              options: const [
                (TextDirection.ltr, 'LTR'),
                (TextDirection.rtl, 'RTL'),
              ],
              onChanged: ref.read(devPreviewProvider.notifier).setDirection,
            ),
            _DevSegmentedControl<String>(
              label: 'Language',
              value: preview.locale,
              options: const [('en', 'EN'), ('ar', 'AR')],
              onChanged: ref.read(devPreviewProvider.notifier).setLocale,
            ),
          ],
        ),
      ),
    );
  }
}

class _DevSegmentedControl<T> extends StatelessWidget {
  const _DevSegmentedControl({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (optionValue, optionLabel) in options)
                _SegmentOption<T>(
                  label: optionLabel,
                  selected: optionValue == value,
                  value: optionValue,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentOption<T> extends StatelessWidget {
  const _SegmentOption({required this.label, required this.selected, required this.value, required this.onChanged});

  final String label;
  final bool selected;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: selected ? colors.surfaceDefault : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space1),
          child: Text(
            label,
            style: AppTypography.bodySm(context).copyWith(
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
