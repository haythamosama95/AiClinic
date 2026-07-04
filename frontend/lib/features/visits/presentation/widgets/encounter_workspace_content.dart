import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review_panel.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_stepper_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';

/// Guided/expert documentation canvas for the encounter workspace primary pane.
class EncounterWorkspaceContent extends ConsumerStatefulWidget {
  const EncounterWorkspaceContent({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;

  @override
  ConsumerState<EncounterWorkspaceContent> createState() => _EncounterWorkspaceContentState();
}

class _EncounterWorkspaceContentState extends ConsumerState<EncounterWorkspaceContent> {
  static const _maxScrollAttempts = 24;

  final _scrollController = ScrollController();
  late final Map<EncounterPhase, GlobalKey> _phaseKeys = {
    for (final phase in EncounterPhase.stepperPhases) phase: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleEditPhase(EncounterPhase phase) {
    ref.read(encounterActivePhaseProvider(widget.visitId).notifier).setPhase(phase);
    final mode = ref.read(workspaceModeProvider);
    if (mode == WorkspaceMode.expert) {
      ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).request(phase);
    }
  }

  void _consumePendingScroll({int attempt = 0}) {
    final mode = ref.read(workspaceModeProvider);
    if (mode != WorkspaceMode.expert) return;

    final target = ref.read(expertModeScrollTargetProvider(widget.visitId));
    if (target == null) return;

    if (_scrollToPhase(target)) {
      ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
      return;
    }

    if (attempt < _maxScrollAttempts) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll(attempt: attempt + 1));
    }
  }

  bool _scrollToPhase(EncounterPhase phase) {
    final targetContext = _phaseKeys[phase]?.currentContext;
    if (targetContext == null) return false;

    Scrollable.ensureVisible(
      targetContext,
      duration: AppMotion.resolvePreset(
        AppMotionPreset.fade,
        reduced: AppMotion.reduced(context),
      ).duration,
      curve: AppEasings.standard,
      alignment: 0.08,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expertModeScrollTargetProvider(widget.visitId), (previous, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumePendingScroll();
      });
    });

    final mode = ref.watch(workspaceModeProvider);
    final activePhase = ref.watch(encounterActivePhaseProvider(widget.visitId));
    final badges = ref.watch(encounterPhaseBadgesProvider(widget.visitId));
    final isReview = activePhase == EncounterPhase.review;
    final isExpert = mode == WorkspaceMode.expert;

    if (isReview) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
        child: EncounterReviewPanel(
          visitId: widget.visitId,
          visit: widget.state.visit,
          state: widget.state,
          canEdit: widget.canEdit,
          canUploadAttachments: widget.canUploadAttachments,
          onEditPhase: widget.canEdit ? _handleEditPhase : null,
        ),
      );
    }

    final activeDocumentationPhase =
        activePhase.isDocumentation ? activePhase : EncounterPhase.subjective;

    final phases = [
      (
        phase: EncounterPhase.subjective,
        child: EncounterPhaseSubjective(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
        ),
      ),
      (
        phase: EncounterPhase.objective,
        child: EncounterPhaseObjective(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
        ),
      ),
      (
        phase: EncounterPhase.plan,
        child: EncounterPhasePlan(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
          canUploadAttachments: widget.canUploadAttachments,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: EncounterWorkspaceModeToggle()),
              if (!isExpert)
                AppButton(
                  label: 'Summary',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  leadingIcon: LucideIcons.fileText,
                  onPressed: () => ref
                      .read(encounterActivePhaseProvider(widget.visitId).notifier)
                      .setPhase(EncounterPhase.review),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          if (!isExpert) ...[
            EncounterStepperHeader(
              activePhase: activeDocumentationPhase,
              badges: badges,
              onPhaseSelected: (phase) =>
                  ref.read(encounterActivePhaseProvider(widget.visitId).notifier).setPhase(phase),
            ),
            const SizedBox(height: AppSpacing.s4),
          ],
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < phases.length; i++) ...[
                    if (i > 0 && isExpert) const SizedBox(height: AppSpacing.s4),
                    Visibility(
                      visible: isExpert || phases[i].phase == activeDocumentationPhase,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: false,
                      child: KeyedSubtree(
                        key: _phaseKeys[phases[i].phase],
                        child: isExpert
                            ? AppCard(
                                padding: AppCardPadding.md,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    AppSectionHeader(title: phases[i].phase.label),
                                    const SizedBox(height: AppSpacing.s3),
                                    phases[i].child,
                                  ],
                                ),
                              )
                            : phases[i].child,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
