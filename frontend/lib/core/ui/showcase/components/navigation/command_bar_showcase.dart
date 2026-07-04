import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class CommandBarShowcase extends ConsumerWidget {
  const CommandBarShowcase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = context.typography;
    final colors = context.colors;

    return ShowcaseSection(
      title: 'Command bar',
      description:
          'Global ⌘K overlay with grouped results, keyboard navigation, and AI entry transition.',
      child: ShowcaseDemo(
        label: 'Hero overlay',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.s2,
          children: [
            AppButton(
              onPressed: () =>
                  ref.read(commandBarProvider.notifier).openCommandBar(),
              variant: AppButtonVariant.secondary,
              child: const Text('Open command bar'),
            ),
            Text.rich(
              TextSpan(
                style: typography.bodySm.copyWith(color: colors.textSecondary),
                children: [
                  const TextSpan(text: 'Press '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: AppKbd(keys: const ['⌘', 'K']),
                  ),
                  const TextSpan(text: ' anywhere in the showcase.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
