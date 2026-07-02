import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/expert_mode_scroll_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/expert_mode_accordion.dart';

/// Scrollable expert-mode page that can jump to a documentation phase section.
class ExpertModeScrollContainer extends ConsumerStatefulWidget {
  const ExpertModeScrollContainer({required this.visitId, required this.phases, this.phaseCardHeight, super.key});

  final String visitId;
  final List<ExpertModePhaseEntry> phases;
  final double? phaseCardHeight;

  @override
  ConsumerState<ExpertModeScrollContainer> createState() => _ExpertModeScrollContainerState();
}

class _ExpertModeScrollContainerState extends ConsumerState<ExpertModeScrollContainer> {
  final _scrollController = ScrollController();
  late final Map<EncounterPhase, GlobalKey> _phaseKeys = {
    for (final phase in EncounterPhase.stepperPhases) phase: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _consumePendingScroll({int attempt = 0}) {
    final target = ref.read(expertModeScrollTargetProvider(widget.visitId));
    if (target == null) {
      return;
    }

    if (_scrollToPhase(target)) {
      ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
      return;
    }

    if (attempt < 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingScroll(attempt: attempt + 1));
    }
  }

  bool _scrollToPhase(EncounterPhase phase) {
    final targetContext = _phaseKeys[phase]?.currentContext;
    if (targetContext == null) {
      return false;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
    return true;
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
        if (_scrollToPhase(next)) {
          ref.read(expertModeScrollTargetProvider(widget.visitId).notifier).clear();
        }
      });
    });

    return SingleChildScrollView(
      key: const Key('expert_mode_scroll_view'),
      controller: _scrollController,
      child: ExpertModeAccordion(phases: widget.phases, phaseCardHeight: widget.phaseCardHeight, phaseKeys: _phaseKeys),
    );
  }
}
