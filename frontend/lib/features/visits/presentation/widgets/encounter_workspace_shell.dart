import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_assessment.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_context.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_step_rail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_sticky_footer.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_accordion.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_safety_rail.dart';
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
  static const _safetySideBreakpoint = 960.0;

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
        final showSideSafetyRail = constraints.maxWidth >= _safetySideBreakpoint;
        final phaseEntries = _documentationPhaseEntries(showClinicalNoteSaveBar: mode == WorkspaceMode.expert);

        return KeyedSubtree(
          key: const Key('encounter_workspace_shell'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceModeBar(
                mode: mode,
                onToggle: () => modeNotifier.toggleMode(),
                onOpenSteps: showSideStepRail
                    ? null
                    : () => _showStepPicker(context, activePhase: activePhase, badges: badges, onSelected: selectPhase),
              ),
              const SizedBox(height: SpacingTokens.sm),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!showSideSafetyRail) ...[
                            PatientSafetyRail(phase: activePhase),
                            const SizedBox(height: VisitPageTokens.sectionGap),
                          ],
                          Expanded(
                            child: SingleChildScrollView(
                              child: mode == WorkspaceMode.expert
                                  ? ExpertModeAccordion(
                                      phases: phaseEntries,
                                      initiallyExpanded: {
                                        activePhase.isDocumentation ? activePhase : EncounterPhase.subjective,
                                      },
                                    )
                                  : _guidedCanvas(activePhase, selectPhase),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showSideSafetyRail) ...[
                      const SizedBox(width: VisitPageTokens.sectionGap),
                      SizedBox(
                        width: EncounterDocumentationLayout.safetyRailWidth,
                        child: PatientSafetyRail(phase: activePhase),
                      ),
                    ],
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

  Widget _guidedCanvas(EncounterPhase activePhase, ValueChanged<EncounterPhase> onEditPhase) {
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

    return _documentationPhaseEntries(
      showClinicalNoteSaveBar: false,
    ).firstWhere((entry) => entry.phase == activePhase).child;
  }

  List<ExpertModePhaseEntry> _documentationPhaseEntries({required bool showClinicalNoteSaveBar}) {
    final visit = state.visit;
    return [
      ExpertModePhaseEntry(
        phase: EncounterPhase.context,
        child: EncounterPhaseContext(visit: visit),
      ),
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
        phase: EncounterPhase.assessment,
        child: EncounterPhaseAssessment(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
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

class _WorkspaceModeBar extends StatelessWidget {
  const _WorkspaceModeBar({required this.mode, required this.onToggle, this.onOpenSteps});

  final WorkspaceMode mode;
  final VoidCallback onToggle;
  final VoidCallback? onOpenSteps;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final isGuided = mode == WorkspaceMode.guided;

    return Row(
      children: [
        if (onOpenSteps != null) ...[
          AppButton(
            key: const Key('encounter_open_steps_button'),
            label: 'Steps',
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.linear_scale_rounded, size: 18),
            onPressed: onOpenSteps,
          ),
          const SizedBox(width: SpacingTokens.sm),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.tile,
            borderRadius: BorderRadius.circular(theme.tileRadius),
            border: Border.all(color: theme.hairlineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeChip(
                key: const Key('encounter_mode_guided'),
                label: 'Guided',
                icon: Icons.view_sidebar_outlined,
                selected: isGuided,
                onTap: isGuided ? null : onToggle,
              ),
              _ModeChip(
                key: const Key('encounter_mode_expert'),
                label: 'Expert',
                icon: Icons.view_agenda_outlined,
                selected: !isGuided,
                onTap: !isGuided ? null : onToggle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.icon, required this.selected, this.onTap, super.key});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Material(
      color: selected ? theme.pulse.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(theme.tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? theme.pulseDeep : theme.mutedInk),
              const SizedBox(width: SpacingTokens.xs),
              Text(label, style: theme.bodyStrong(size: 13, color: selected ? theme.pulseDeep : theme.mutedInk)),
            ],
          ),
        ),
      ),
    );
  }
}
