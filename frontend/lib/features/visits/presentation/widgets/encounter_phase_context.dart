import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_safety_editors.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Context phase — visit type, patient snapshot, and safety record editors (014 US2/US6).
class EncounterPhaseContext extends ConsumerWidget {
  const EncounterPhaseContext({required this.visit, this.canEdit = false, super.key});

  final VisitDetail visit;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final visitType = visit.visitType?.trim();
    final hasVisitType = visitType != null && visitType.isNotEmpty;

    return KeyedSubtree(
      key: const Key('encounter_phase_context'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasVisitType) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VisitMarginAbbr(letter: EncounterPhase.context.abbr),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VISIT TYPE', style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
                      const SizedBox(height: SpacingTokens.xs + 1),
                      Text(visitType, key: const Key('encounter_context_visit_type'), style: theme.bodyStrong()),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
          ],
          PatientSafetyEditors(patientId: visit.patientId, canEdit: canEdit),
        ],
      ),
    );
  }
}
