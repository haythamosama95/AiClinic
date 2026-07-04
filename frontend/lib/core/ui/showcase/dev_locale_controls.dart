import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/actions/segmented_control.dart';

/// Dev/design-system preview controls — mirrors web `DevLocaleControls`.
///
/// Density, text direction, and locale live on the design system page, not in
/// the app top bar toolbar.
class DevLocaleControls extends ConsumerWidget {
  const DevLocaleControls({super.key});

  static const _devDensities = [AppDensity.compact, AppDensity.comfortable];

  static AppDensity _toDevDensity(AppDensity density) =>
      density == AppDensity.compact ? AppDensity.compact : AppDensity.comfortable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final localeState = ref.watch(appLocaleProvider);
    final devDensity = _toDevDensity(density);
    final direction = localeState.textDirection;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: colors.borderDefault),
        color: colors.surfaceDefault,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Wrap(
          spacing: AppSpacing.s4,
          runSpacing: AppSpacing.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_outlined, size: 16, color: colors.iconMuted),
                const SizedBox(width: AppSpacing.s2),
                Text(
                  'Preview theming',
                  style: typography.bodySm.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppSegmentedControl<AppDensity>(
                  semanticLabel: 'Shell density',
                  size: AppSegmentedControlSize.sm,
                  selected: devDensity,
                  onChanged: (value) =>
                      ref.read(appDensityProvider.notifier).setDensity(value),
                  options: _devDensities
                      .map(
                        (value) => AppSegmentedOption(
                          value: value,
                          label: Text(value.label),
                        ),
                      )
                      .toList(),
                ),
                AppSegmentedControl<TextDirection>(
                  semanticLabel: 'Text direction',
                  size: AppSegmentedControlSize.sm,
                  selected: direction,
                  onChanged: (value) {
                    ref.read(appLocaleProvider.notifier).setLocale(
                          value == TextDirection.rtl ? AppLocale.ar : AppLocale.en,
                        );
                  },
                  options: const [
                    AppSegmentedOption(
                      value: TextDirection.ltr,
                      label: Text('LTR'),
                    ),
                    AppSegmentedOption(
                      value: TextDirection.rtl,
                      label: Text('RTL'),
                    ),
                  ],
                ),
                AppSegmentedControl<AppLocale>(
                  semanticLabel: 'Language',
                  size: AppSegmentedControlSize.sm,
                  selected: localeState.locale,
                  onChanged: (value) =>
                      ref.read(appLocaleProvider.notifier).setLocale(value),
                  options: const [
                    AppSegmentedOption(value: AppLocale.en, label: Text('EN')),
                    AppSegmentedOption(value: AppLocale.ar, label: Text('AR')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
