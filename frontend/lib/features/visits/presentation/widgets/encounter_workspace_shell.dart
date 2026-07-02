import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_accordion.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_scroll_container.dart';

/// Three-region encounter workspace with guided/expert modes (014 US4-US5 / FR-014-020).
class EncounterWorkspaceShell extends ConsumerWidget {
  const EncounterWorkspaceShell({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;

  static const _summaryPageIndex = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(workspaceModeProvider);
    final activePhase = ref.watch(encounterActivePhaseProvider(visitId));
    final isOnSummary = activePhase == EncounterPhase.review;

    void handleSummaryEdit(EncounterPhase phase) {
      ref.read(encounterActivePhaseProvider(visitId).notifier).setPhase(phase);
      if (mode == WorkspaceMode.expert) {
        ref.read(expertModeScrollTargetProvider(visitId).notifier).request(phase);
      }
    }

    return KeyedSubtree(
      key: const Key('encounter_workspace_shell'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AppPageFadeTransition(
              key: const Key('encounter_workspace_transition'),
              index: isOnSummary ? _summaryPageIndex : 0,
              children: [
                _DocumentationView(
                  visitId: visitId,
                  state: state,
                  canEdit: canEdit,
                  canUploadAttachments: canUploadAttachments,
                  onRefresh: onRefresh,
                  mode: mode,
                  activePhase: activePhase,
                ),
                EncounterReview(
                  visitId: visitId,
                  visit: state.visit,
                  state: state,
                  canEdit: canEdit,
                  canUploadAttachments: canUploadAttachments,
                  onRefresh: onRefresh,
                  onEditPhase: handleSummaryEdit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentationView extends StatelessWidget {
  const _DocumentationView({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    required this.mode,
    required this.activePhase,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final WorkspaceMode mode;
  final EncounterPhase activePhase;

  @override
  Widget build(BuildContext context) {
    return AppPageFadeTransition(
      key: const Key('encounter_mode_transition'),
      index: mode == WorkspaceMode.expert ? 1 : 0,
      children: [
        AppPageFadeTransition(
          key: const Key('encounter_phase_page_transition'),
          index: activePhase.isDocumentation ? activePhase.stepperIndex : 0,
          children: [
            for (final phase in EncounterPhase.stepperPhases)
              KeyedSubtree(key: Key('encounter_phase_page_${phase.name}'), child: _documentationPhasePage(phase)),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return ExpertModeScrollContainer(
              visitId: visitId,
              phaseCardHeight: constraints.maxHeight,
              phases: _documentationPhaseEntries(showClinicalNoteSaveBar: !canEdit, expertMode: true),
            );
          },
        ),
      ],
    );
  }

  Widget _documentationPhasePage(EncounterPhase phase) {
    return _documentationPhaseEntries(showClinicalNoteSaveBar: false).firstWhere((entry) => entry.phase == phase).child;
  }

  List<ExpertModePhaseEntry> _documentationPhaseEntries({
    required bool showClinicalNoteSaveBar,
    bool expertMode = false,
  }) {
    return [
      ExpertModePhaseEntry(
        phase: EncounterPhase.subjective,
        child: EncounterPhaseSubjective(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showClinicalNoteSaveBar: showClinicalNoteSaveBar,
          expertMode: expertMode,
        ),
      ),
      ExpertModePhaseEntry(
        phase: EncounterPhase.objective,
        child: EncounterPhaseObjective(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          onRefresh: onRefresh,
          showClinicalNoteSaveBar: showClinicalNoteSaveBar,
          expertMode: expertMode,
        ),
      ),
      ExpertModePhaseEntry(
        phase: EncounterPhase.plan,
        child: EncounterPhasePlan(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          canUploadAttachments: canUploadAttachments,
          onRefresh: onRefresh,
          showClinicalNoteSaveBar: showClinicalNoteSaveBar,
          expertMode: expertMode,
        ),
      ),
    ];
  }
}
