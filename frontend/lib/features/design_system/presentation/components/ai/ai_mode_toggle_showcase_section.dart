import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_ai_mode_toggle.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _AiModeToggleCopy {
  const _AiModeToggleCopy({
    required this.demoLabel,
    required this.aiMode,
    required this.standard,
  });

  final String demoLabel;
  final String aiMode;
  final String standard;
}

const _copyEn = _AiModeToggleCopy(
  demoLabel: 'Standard ↔ AI',
  aiMode: 'AI mode',
  standard: 'Standard',
);

const _copyAr = _AiModeToggleCopy(
  demoLabel: 'القياسي ↔ الذكاء',
  aiMode: 'وضع الذكاء',
  standard: 'القياسي',
);

_AiModeToggleCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// AI mode toggle showcase (web `AiModeToggleShowcase`).
class AiModeToggleShowcaseSection extends ConsumerWidget {
  const AiModeToggleShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'ai-mode-toggle',
      title: 'AI mode toggle',
      componentName: 'AiModeToggle',
      child: ShowcaseDemo(
        label: copy.demoLabel,
        child: Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppAiModeToggle(
              initialValue: true,
              aiModeLabel: copy.aiMode,
              standardLabel: copy.standard,
            ),
            const AppAiModeToggle(showLabel: false),
          ],
        ),
      ),
    );
  }
}
