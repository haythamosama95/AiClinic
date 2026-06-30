import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_step_rail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_sticky_footer.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_accordion.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Three-region encounter workspace with guided/expert modes (014 US4–US5 / FR-014–020).
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

  static const _wideBreakpoint = 1100.0;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideStepRail = constraints.maxWidth >= _wideBreakpoint && mode == WorkspaceMode.guided;
        final phaseEntries = _documentationPhaseEntries(showClinicalNoteSaveBar: mode == WorkspaceMode.expert);

        return KeyedSubtree(
          key: const Key('encounter_workspace_shell'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!showSideStepRail && mode == WorkspaceMode.guided) ...[
                AppButton(
                  key: const Key('encounter_open_steps_button'),
                  label: 'Steps',
                  variant: AppButtonVariant.outline,
                  icon: const Icon(Icons.linear_scale_rounded, size: 18),
                  onPressed: () =>
                      _showStepPicker(context, activePhase: activePhase, badges: badges, onSelected: selectPhase),
                ),
                const SizedBox(height: SpacingTokens.sm),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSideStepRail) ...[
                      SizedBox(
                        width: EncounterStepRail.width,
                        child: EncounterStepRail(
                          visitId: visitId,
                          activePhase: activePhase,
                          badges: badges,
                          onPhaseSelected: selectPhase,
                        ),
                      ),
                      const SizedBox(width: VisitPageTokens.sectionGap),
                    ],
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, canvasConstraints) {
                          return SingleChildScrollView(
                            child: mode == WorkspaceMode.expert
                                ? ExpertModeAccordion(
                                    phases: phaseEntries,
                                    initiallyExpanded: {
                                      activePhase.isDocumentation ? activePhase : EncounterPhase.subjective,
                                    },
                                  )
                                : _guidedCanvas(activePhase, selectPhase, canvasHeight: canvasConstraints.maxHeight),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (mode == WorkspaceMode.guided)
                EncounterStickyFooter(
                  visitId: visitId,
                  state: state,
                  canEdit: canEdit,
                  activePhase: activePhase,
                  onPhaseSelected: selectPhase,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _guidedCanvas(
    EncounterPhase activePhase,
    ValueChanged<EncounterPhase> onEditPhase, {
    required double canvasHeight,
  }) {
    if (activePhase == EncounterPhase.review) {
      return EncounterReview(
        visitId: visitId,
        visit: state.visit,
        state: state,
        canEdit: canEdit,
        canUploadAttachments: canUploadAttachments,
        onRefresh: onRefresh,
        onEditPhase: onEditPhase,
        onSubmit: onSubmit,
        showSubmit: showSubmit,
      );
    }

    final child = _documentationPhaseEntries(
      showClinicalNoteSaveBar: false,
      canvasHeight: activePhase == EncounterPhase.subjective ? canvasHeight : null,
    ).firstWhere((entry) => entry.phase == activePhase).child;

    if (activePhase == EncounterPhase.subjective) {
      return SizedBox(height: canvasHeight, child: child);
    }

    return child;
  }

  List<ExpertModePhaseEntry> _documentationPhaseEntries({required bool showClinicalNoteSaveBar, double? canvasHeight}) {
    return [
      ExpertModePhaseEntry(
        phase: EncounterPhase.subjective,
        child: EncounterPhaseSubjective(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showClinicalNoteSaveBar: showClinicalNoteSaveBar,
          canvasHeight: canvasHeight,
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

  Future<void> _showStepPicker(
    BuildContext context, {
    required EncounterPhase activePhase,
    required PhaseBadges badges,
    required ValueChanged<EncounterPhase> onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: EncounterStepRail(
              visitId: visitId,
              activePhase: activePhase,
              badges: badges,
              onPhaseSelected: (phase) {
                Navigator.of(context).pop();
                onSelected(phase);
              },
            ),
          ),
        );
      },
    );
  }
}
