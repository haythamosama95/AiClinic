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

/// Phase section card for expert single-page mode (014 US5 / FR-019).
class EncounterPhaseReadGroup extends StatelessWidget {
  const EncounterPhaseReadGroup({
    required this.phase,
    required this.child,
    this.contentHeight,
    this.showPhaseChrome = true,
    super.key,
  });

  final EncounterPhase phase;
  final Widget child;

  /// When set, the card body is given a fixed height in expert mode.
  final double? contentHeight;

  /// When false (guided stepper), omits the outer phase card chrome.
  final bool showPhaseChrome;

  @override
  Widget build(BuildContext context) {
    final body = contentHeight != null ? SizedBox(height: contentHeight, child: child) : child;

    if (!showPhaseChrome) {
      return body;
    }

    final theme = context.visitTheme;

    return AppCard(
      key: Key('encounter_phase_read_${phase.name}'),
      title: Padding(
        padding: const EdgeInsets.only(bottom: SpacingTokens.md),
        child: Row(
          children: [
            Icon(phase.icon, size: 20, color: theme.pulse),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(child: Text(phase.label, style: theme.title())),
          ],
        ),
      ),
      child: body,
    );
  }
}
