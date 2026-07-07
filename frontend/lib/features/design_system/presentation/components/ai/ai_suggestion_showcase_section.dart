import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_ai_suggestion.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _AiSuggestionCopy {
  const _AiSuggestionCopy({
    required this.message,
    required this.acceptLabel,
    required this.dismissLabel,
    required this.dismissSuggestionLabel,
  });

  final String message;
  final String acceptLabel;
  final String dismissLabel;
  final String dismissSuggestionLabel;
}

const _copyEn = _AiSuggestionCopy(
  message: "AI can draft a SOAP note from today's visit summary.",
  acceptLabel: 'Use suggestion',
  dismissLabel: 'Dismiss',
  dismissSuggestionLabel: 'Dismiss suggestion',
);

const _copyAr = _AiSuggestionCopy(
  message: 'يمكن للذكاء الاصطناعي صياغة ملاحظة SOAP من ملخص زيارة اليوم.',
  acceptLabel: 'استخدم الاقتراح',
  dismissLabel: 'رفض',
  dismissSuggestionLabel: 'رفض الاقتراح',
);

_AiSuggestionCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Inline AI suggestion showcase (web `AiSuggestionShowcase` in `AiShowcase.tsx`).
class AiSuggestionShowcaseSection extends ConsumerWidget {
  const AiSuggestionShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'ai-suggestion',
      title: 'Inline AI suggestion',
      componentName: 'AiSuggestion',
      child: AppAiSuggestion(
        message: copy.message,
        acceptLabel: copy.acceptLabel,
        dismissLabel: copy.dismissLabel,
        dismissSuggestionLabel: copy.dismissSuggestionLabel,
        onAccept: () {},
        onDismiss: () {},
      ),
    );
  }
}
