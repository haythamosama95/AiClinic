import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Phase section heading for encounter workspace canvases (014).
class EncounterPhaseHeader extends StatelessWidget {
  const EncounterPhaseHeader({required this.phase, this.description, super.key});

  final EncounterPhase phase;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.pulse.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(theme.tileRadius),
              border: Border.all(color: theme.pulse.withValues(alpha: 0.28)),
            ),
            alignment: Alignment.center,
            child: Text(phase.abbr, style: theme.readout(color: theme.pulseDeep, size: 12)),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phase.label, style: theme.title(size: 18)),
                if (description != null) ...[const SizedBox(height: 2), Text(description!, style: theme.caption())],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
