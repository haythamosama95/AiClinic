import 'package:flutter/material.dart';

import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';

/// Expert single-page mode — documentation phase sections on one scrollable page (014 US5 / FR-019).
class ExpertModeAccordion extends StatelessWidget {
  const ExpertModeAccordion({required this.phases, this.phaseCardHeight, this.phaseKeys, super.key});

  final List<ExpertModePhaseEntry> phases;
  final double? phaseCardHeight;
  final Map<EncounterPhase, GlobalKey>? phaseKeys;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('expert_mode_accordion'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            KeyedSubtree(
              key: Key('expert_mode_phase_${phases[i].phase.name}'),
              child: ColoredBox(
                color: Colors.transparent,
                key: phaseKeys?[phases[i].phase],
                child: EncounterPhaseReadGroup(
                  phase: phases[i].phase,
                  contentHeight: phaseCardHeight,
                  child: phases[i].child,
                ),
              ),
            ),
            if (i < phases.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class ExpertModePhaseEntry {
  const ExpertModePhaseEntry({required this.phase, required this.child});

  final EncounterPhase phase;
  final Widget child;
}
