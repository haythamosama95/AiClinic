import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Documentation layout stacking encounter phase canvases (014 US3).
class EncounterDocumentationLayout extends StatelessWidget {
  const EncounterDocumentationLayout({required this.phases, super.key});

  final List<Widget> phases;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _withGaps(phases));
  }

  List<Widget> _withGaps(List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(const SizedBox(height: VisitPageTokens.sectionGap));
      }
    }
    return result;
  }
}

/// Collapsible read-only phase group for the visit detail view (FR-009).
class EncounterPhaseReadGroup extends StatefulWidget {
  const EncounterPhaseReadGroup({required this.phase, required this.child, this.initiallyExpanded = true, super.key});

  final EncounterPhase phase;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<EncounterPhaseReadGroup> createState() => _EncounterPhaseReadGroupState();
}

class _EncounterPhaseReadGroupState extends State<EncounterPhaseReadGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return AppNotchedCard(
      key: Key('encounter_phase_read_${widget.phase.name}'),
      titleIcon: Icons.layers_outlined,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.pulse.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(theme.tileRadius - 2),
              border: Border.all(color: theme.pulse.withValues(alpha: 0.28)),
            ),
            alignment: Alignment.center,
            child: Text(widget.phase.abbr, style: theme.readout(color: theme.pulseDeep, size: 11)),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(child: Text(widget.phase.label, style: theme.title())),
        ],
      ),
      actions: [
        AppIconButton(
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          tooltip: _expanded ? 'Collapse' : 'Expand',
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
      ],
      body: _expanded
          ? Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
              child: widget.child,
            )
          : const SizedBox.shrink(),
    );
  }
}
