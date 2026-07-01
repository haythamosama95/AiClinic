import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_accordion.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Three-region encounter workspace with guided/expert modes (014 US4-US5 / FR-014-020).
class EncounterWorkspaceShell extends ConsumerWidget {
  const EncounterWorkspaceShell({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    this.onSubmit,
    this.showSubmit = false,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final VoidCallback? onSubmit;
  final bool showSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(workspaceModeProvider);
    final activePhase = ref.watch(encounterActivePhaseProvider(visitId));
    final badges = ref.watch(encounterPhaseBadgesProvider(visitId));
    final phaseNotifier = ref.read(encounterActivePhaseProvider(visitId).notifier);
    final modeNotifier = ref.read(workspaceModeProvider.notifier);

    void selectPhase(EncounterPhase phase) {
      phaseNotifier.setPhase(phase);
      if (mode == WorkspaceMode.expert && phase.isDocumentation) {
        modeNotifier.setMode(WorkspaceMode.guided);
      }
    }

    return KeyedSubtree(
      key: const Key('encounter_workspace_shell'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: mode == WorkspaceMode.expert
                ? SingleChildScrollView(
                    child: ExpertModeAccordion(
                      phases: _documentationPhaseEntries(showClinicalNoteSaveBar: true),
                      initiallyExpanded: {activePhase.isDocumentation ? activePhase : EncounterPhase.subjective},
                    ),
                  )
                : AppStepper(
                    key: const Key('encounter_stepper'),
                    axis: Axis.horizontal,
                    showCard: false,
                    currentStep: activePhase.orderIndex,
                    onStepChanged: (index) => selectPhase(EncounterPhase.ordered[index]),
                    steps: _encounterSteps(context, badges: badges, selectPhase: selectPhase),
                  ),
          ),
        ],
      ),
    );
  }

  List<AppStepperStep> _encounterSteps(
    BuildContext context, {
    required PhaseBadges badges,
    required ValueChanged<EncounterPhase> selectPhase,
  }) {
    final theme = context.visitTheme;

    return [
      for (final phase in EncounterPhase.ordered)
        AppStepperStep(
          stepKey: Key('encounter_step_${phase.name}'),
          title: phase.label,
          icon: phase.icon,
          trailing: _phaseBadge(badges[phase] ?? PhaseCompletionBadge.empty, theme),
          page: _phasePage(phase, selectPhase),
        ),
    ];
  }

  Widget? _phaseBadge(PhaseCompletionBadge badge, VisitTheme theme) {
    return switch (badge) {
      PhaseCompletionBadge.empty => null,
      PhaseCompletionBadge.hasContent => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: theme.pulseDeep,
        semanticLabel: 'Has content',
      ),
      PhaseCompletionBadge.error => Icon(
        Icons.error_outline,
        size: 16,
        color: theme.danger,
        semanticLabel: 'Validation error',
      ),
    };
  }

  Widget _phasePage(EncounterPhase phase, ValueChanged<EncounterPhase> onEditPhase) {
    if (phase == EncounterPhase.review) {
      return SingleChildScrollView(
        child: EncounterReview(
          visitId: visitId,
          visit: state.visit,
          state: state,
          canEdit: canEdit,
          canUploadAttachments: canUploadAttachments,
          onRefresh: onRefresh,
          onEditPhase: onEditPhase,
          onSubmit: onSubmit,
          showSubmit: showSubmit,
        ),
      );
    }

    final child = _documentationPhaseEntries(
      showClinicalNoteSaveBar: false,
    ).firstWhere((entry) => entry.phase == phase).child;

    if (phase == EncounterPhase.subjective) {
      return child;
    }

    return SingleChildScrollView(child: child);
  }

  List<ExpertModePhaseEntry> _documentationPhaseEntries({required bool showClinicalNoteSaveBar}) {
    return [
      ExpertModePhaseEntry(
        phase: EncounterPhase.subjective,
        child: EncounterPhaseSubjective(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showClinicalNoteSaveBar: showClinicalNoteSaveBar,
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
        ),
      ),
    ];
  }
}
