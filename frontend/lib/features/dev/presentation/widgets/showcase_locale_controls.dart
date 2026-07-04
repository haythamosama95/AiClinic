import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/locale_direction_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Debug-only controls mirroring web [DevLocaleControls].
class ShowcaseLocaleControls extends ConsumerStatefulWidget {
  const ShowcaseLocaleControls({super.key});

  @override
  ConsumerState<ShowcaseLocaleControls> createState() => _ShowcaseLocaleControlsState();
}

class _ShowcaseLocaleControlsState extends ConsumerState<ShowcaseLocaleControls> {
  var _forceReducedMotion = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final locale = ref.watch(localeDirectionProvider).locale;
    final themeMode = ref.watch(themeModeProvider);
    final systemReduced = MediaQuery.disableAnimationsOf(context);
    final effectiveReduced = _forceReducedMotion || systemReduced;

    return ProviderScope(
      overrides: [reducedMotionProvider.overrideWithValue(effectiveReduced)],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: colors.borderDefault),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
          child: Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    icon: LucideIcons.languages,
                    dimension: AppSpacing.s4,
                    color: colors.iconMuted,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    'Preview theming',
                    style: typography.bodySm.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
              AppSegmentedControl<AppDensity>(
                size: AppSegmentedControlSize.sm,
                semanticLabel: 'Shell density',
                value: density,
                onChanged: (value) => ref.read(appDensityProvider.notifier).setDensity(value),
                options: const [
                  AppSegmentedOption(value: AppDensity.compact, label: 'Compact'),
                  AppSegmentedOption(value: AppDensity.comfortable, label: 'Comfortable'),
                ],
              ),
              AppSegmentedControl<ThemeMode>(
                size: AppSegmentedControlSize.sm,
                semanticLabel: 'Appearance',
                value: themeMode,
                onChanged: (value) => setAppThemeMode(ref, value),
                options: const [
                  AppSegmentedOption(value: ThemeMode.system, label: 'System'),
                  AppSegmentedOption(value: ThemeMode.light, label: 'Light'),
                  AppSegmentedOption(value: ThemeMode.dark, label: 'Dark'),
                ],
              ),
              AppSegmentedControl<String>(
                size: AppSegmentedControlSize.sm,
                semanticLabel: 'Language',
                value: locale.languageCode,
                onChanged: (value) => ref.read(localeDirectionProvider.notifier).setLocale(Locale(value)),
                options: const [
                  AppSegmentedOption(value: 'en', label: 'EN'),
                  AppSegmentedOption(value: 'ar', label: 'AR'),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSwitch(
                    label: 'Reduce motion',
                    value: _forceReducedMotion,
                    onChanged: (value) => setState(() => _forceReducedMotion = value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
