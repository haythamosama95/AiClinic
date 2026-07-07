import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_ai_panel.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _AiPanelCopy {
  const _AiPanelCopy({required this.scope});

  final String scope;
}

const _copyEn = _AiPanelCopy(scope: 'Downtown branch');

const _copyAr = _AiPanelCopy(scope: 'فرع وسط البلد');

_AiPanelCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

class AiPanelShowcaseSection extends ConsumerWidget {
  const AiPanelShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'ai-panel',
      title: 'AI panel / chat',
      componentName: 'AiPanel',
      child: SizedBox(
        height: 420,
        child: SizedBox(
          width: 480,
          child: AppAiPanel(scope: copy.scope),
        ),
      ),
    );
  }
}
