import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/findings_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/intake_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';

/// Expert workspace: all encounter sections stacked in one scroller (Flutter-only).
class ExpertVisitAccordion extends ConsumerStatefulWidget {
  const ExpertVisitAccordion({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<ExpertVisitAccordion> createState() => _ExpertVisitAccordionState();
}

class _ExpertVisitAccordionState extends ConsumerState<ExpertVisitAccordion> with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _sectionKeys = <EncounterPhase, GlobalKey>{
    for (final phase in EncounterPhase.stepperPhases) phase: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToPhase(EncounterPhase phase) {
    final key = _sectionKeys[phase];
    final context = key?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(context, duration: AppMotion.base, curve: AppMotionEasing.out, alignment: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expertModeScrollTargetProvider(widget.visitId), (previous, next) {
      if (next == null) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scrollToPhase(next);
        ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
      });
    });

    return SingleChildScrollView(
      controller: _scrollController,
      child: VisitStagger(
        vsync: this,
        stepMs: 40,
        children: [
          for (final phase in EncounterPhase.stepperPhases)
            VisitStaggeredItem(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                child: Column(
                  key: _sectionKeys[phase],
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PhaseHeader(phase: phase),
                    const SizedBox(height: AppSpacing.space4),
                    switch (phase) {
                      EncounterPhase.subjective => IntakeSection(visitId: widget.visitId),
                      EncounterPhase.objective => FindingsSection(visitId: widget.visitId),
                      EncounterPhase.plan => TreatmentSection(visitId: widget.visitId),
                      EncounterPhase.review ||
                      EncounterPhase.context ||
                      EncounterPhase.billing => const SizedBox.shrink(),
                    },
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.phase});

  final EncounterPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.full)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space2),
            child: Icon(phase.icon, size: 18, color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: AppSectionHeader(
            title: phase.label,
            description: switch (phase) {
              EncounterPhase.subjective => 'Chief complaint, history, and medical background.',
              EncounterPhase.objective => 'Examination findings, vital signs, and diagnosis.',
              EncounterPhase.plan => 'Treatment notes, investigations, prescriptions, and attachments.',
              EncounterPhase.review || EncounterPhase.context || EncounterPhase.billing => null,
            },
          ),
        ),
      ],
    );
  }
}
