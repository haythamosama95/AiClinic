import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_ai_message_bubble.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _AiMessageBubbleCopy {
  const _AiMessageBubbleCopy({
    required this.userMessage,
    required this.assistantMessage,
  });

  final String userMessage;
  final String assistantMessage;
}

const _copyEn = _AiMessageBubbleCopy(
  userMessage: 'Which patients need follow-up this week?',
  assistantMessage:
      'Three patients have follow-ups due: Layla Hassan, Omar Farouk, and Nadia El-Sayed.',
);

const _copyAr = _AiMessageBubbleCopy(
  userMessage: 'أي المرضى يحتاجون إلى متابعة هذا الأسبوع؟',
  assistantMessage:
      'ثلاثة مرضى لديهم مواعيد متابعة مستحقة: ليلى حسن، عمر فاروق، ونادية السيد.',
);

_AiMessageBubbleCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// AI message bubble showcase (web `AiMessageBubbleShowcase` in `AiShowcase.tsx`).
class AiMessageBubbleShowcaseSection extends ConsumerWidget {
  const AiMessageBubbleShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'ai-message-bubble',
      title: 'AI message bubbles',
      componentName: 'AiMessageBubble',
      child: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppAiMessageBubble(
              role: AiMessageRole.user,
              timestamp: '2:14 PM',
              child: Text(copy.userMessage),
            ),
            const SizedBox(height: AppSpacing.space4),
            AppAiMessageBubble(
              role: AiMessageRole.assistant,
              timestamp: '2:14 PM',
              onCopy: () {},
              child: Text(copy.assistantMessage),
            ),
          ],
        ),
      ),
    );
  }
}
