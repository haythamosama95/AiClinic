import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';

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

/// Single shared documentation tree; guided vs expert only changes visibility and chrome.
class _DocumentationView extends ConsumerStatefulWidget {
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
  ConsumerState<_DocumentationView> createState() => _DocumentationViewState();
}

class _DocumentationViewState extends ConsumerState<_DocumentationView> {
  static const _maxScrollAttempts = 24;

  final _scrollController = ScrollController();
  late final Map<EncounterPhase, GlobalKey> _phaseScrollKeys = {
    for (final phase in EncounterPhase.stepperPhases) phase: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll());
  }

  @override
  void didUpdateWidget(covariant _DocumentationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activePhase != widget.activePhase && widget.mode == WorkspaceMode.guided) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPhase(widget.activePhase));
    }
    if (oldWidget.mode != widget.mode && widget.mode == WorkspaceMode.expert) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _consumePendingScroll({int attempt = 0}) {
    if (widget.mode != WorkspaceMode.expert) {
      return;
    }

    final target = ref.read(expertModeScrollTargetProvider(widget.visitId));
    if (target == null) {
      return;
    }

    if (_scrollToPhase(target)) {
      ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
      return;
    }

    if (attempt < _maxScrollAttempts) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll(attempt: attempt + 1));
      return;
    }

    if (_scrollToPhaseFallback(target)) {
      ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
    }
  }

  bool _scrollToPhaseFallback(EncounterPhase phase) {
    if (!_scrollController.hasClients) {
      return false;
    }

    final phases = _phaseEntries();
    final index = phases.indexWhere((entry) => entry.phase == phase);
    if (index < 0) {
      return false;
    }

    final position = _scrollController.position;
    final targetOffset = (position.maxScrollExtent / phases.length) * index;
    _scrollController.animateTo(
      targetOffset.clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    return true;
  }

  bool _scrollToPhase(EncounterPhase phase) {
    final targetContext = _phaseScrollKeys[phase]?.currentContext;
    if (targetContext == null) {
      return false;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: widget.mode == WorkspaceMode.expert ? 0.08 : 0,
    );
    return true;
  }

  List<_SharedPhaseEntry> _phaseEntries() {
    return [
      _SharedPhaseEntry(
        phase: EncounterPhase.subjective,
        pageKey: const Key('encounter_phase_page_subjective'),
        child: EncounterPhaseSubjective(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
          showClinicalNoteSaveBar: false,
        ),
      ),
      _SharedPhaseEntry(
        phase: EncounterPhase.objective,
        pageKey: const Key('encounter_phase_page_objective'),
        child: EncounterPhaseObjective(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
          onRefresh: widget.onRefresh,
          showClinicalNoteSaveBar: false,
        ),
      ),
      _SharedPhaseEntry(
        phase: EncounterPhase.plan,
        pageKey: const Key('encounter_phase_page_plan'),
        child: EncounterPhasePlan(
          visitId: widget.visitId,
          state: widget.state,
          canEdit: widget.canEdit,
          canUploadAttachments: widget.canUploadAttachments,
          onRefresh: widget.onRefresh,
          showClinicalNoteSaveBar: false,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expertModeScrollTargetProvider(widget.visitId), (previous, next) {
      if (next == null || widget.mode != WorkspaceMode.expert) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _consumePendingScroll();
      });
    });

    final isExpert = widget.mode == WorkspaceMode.expert;
    final activeDocumentationPhase = widget.activePhase.isDocumentation
        ? widget.activePhase
        : EncounterPhase.subjective;
    final phases = _phaseEntries();

    return KeyedSubtree(
      key: const Key('encounter_documentation_layout'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;

          return SingleChildScrollView(
            key: Key(isExpert ? 'expert_mode_scroll_view' : 'guided_mode_scroll_view'),
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              key: isExpert ? const Key('expert_mode_accordion') : const Key('encounter_phase_page_transition'),
              children: [
                for (var index = 0; index < phases.length; index++) ...[
                  if (index > 0 && isExpert) const SizedBox(height: 12),
                  KeyedSubtree(
                    key: Key('expert_mode_phase_${phases[index].phase.name}'),
                    child: Visibility(
                      visible: isExpert || phases[index].phase == activeDocumentationPhase,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: false,
                      child: KeyedSubtree(
                        key: phases[index].pageKey,
                        child: ColoredBox(
                          color: Colors.transparent,
                          key: _phaseScrollKeys[phases[index].phase],
                          child: EncounterPhaseReadGroup(
                            phase: phases[index].phase,
                            contentHeight: isExpert ? viewportHeight : null,
                            showPhaseChrome: isExpert,
                            child: phases[index].child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SharedPhaseEntry {
  const _SharedPhaseEntry({required this.phase, required this.pageKey, required this.child});

  final EncounterPhase phase;
  final Key pageKey;
  final Widget child;
}
