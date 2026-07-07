import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_thinking_indicator.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ThinkingIndicatorCopy {
  const _ThinkingIndicatorCopy({
    required this.demoLabel,
    required this.thinkingLabel,
  });

  final String demoLabel;
  final String thinkingLabel;
}

const _copyEn = _ThinkingIndicatorCopy(
  demoLabel: 'Signal pulse',
  thinkingLabel: 'Thinking…',
);

const _copyAr = _ThinkingIndicatorCopy(
  demoLabel: 'نبض الإشارة',
  thinkingLabel: 'يفكّر…',
);

_ThinkingIndicatorCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Thinking indicator showcase (web `ThinkingIndicatorShowcase` in `AiShowcase.tsx`).
class ThinkingIndicatorShowcaseSection extends ConsumerWidget {
  const ThinkingIndicatorShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'thinking-indicator',
      title: 'Thinking indicator',
      componentName: 'ThinkingIndicator',
      child: ShowcaseDemo(
        label: copy.demoLabel,
        child: AppThinkingIndicator(label: copy.thinkingLabel),
      ),
    );
  }
}
