import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_patient_info_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Context phase — visit type and patient snapshot (014 US2).
class EncounterPhaseContext extends ConsumerWidget {
  const EncounterPhaseContext({required this.visit, super.key});

  final VisitDetail visit;

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
          const EncounterPhaseHeader(phase: EncounterPhase.context, description: 'Visit context and patient snapshot'),
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
          VisitPatientBasicInfoCard(patientId: visit.patientId),
        ],
      ),
    );
  }
}
