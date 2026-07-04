import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Dockable AI assistant pane for the encounter workspace.
class EncounterAiPane extends ConsumerWidget {
  const EncounterAiPane({
    required this.visitId,
    super.key,
  });

  final String visitId;

  static const _suggestedPrompts = [
    'Summarize this visit so far',
    'Suggest differential diagnoses',
    'Draft a treatment plan outline',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docState = ref.watch(visitDocumentationProvider(visitId)).value;
    final patientLabel = docState == null ? 'Visit' : 'Patient context';

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s2),
      child: AppAiPanel(
        messages: const [],
        scope: patientLabel,
        suggestedPrompts: _suggestedPrompts,
        emptyHint: 'Ask about clinical documentation, differentials, or treatment options.',
        onSend: (_) {
          // AI backend integration is out of scope for this presentation layer.
        },
      ),
    );
  }
}
