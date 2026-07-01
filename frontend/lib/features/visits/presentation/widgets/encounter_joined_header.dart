import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header_path.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_stepper_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Encounter metadata header joined to the guided-mode stepper shelf (014).
class EncounterJoinedHeader extends ConsumerStatefulWidget {
  const EncounterJoinedHeader({
    required this.visitId,
    required this.visit,
    required this.onBack,
    this.onEdit,
    this.beforeTrailing,
    this.trailing,
    this.shoulderShelfSpan = 0,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final Widget? beforeTrailing;
  final Widget? trailing;

  /// Extra horizontal length between shoulder fillets on each side (pixels).
  final double shoulderShelfSpan;

  @override
  ConsumerState<EncounterJoinedHeader> createState() => _EncounterJoinedHeaderState();
}

class _EncounterJoinedHeaderState extends ConsumerState<EncounterJoinedHeader> {
  /// Horizontal bleed on each side of the stepper shelf divider (fraction of stepper width).
  static const _dividerSideBleedFraction = 0.1;

  final GlobalKey _headerMeasureKey = GlobalKey();
  final GlobalKey _stepperMeasureKey = GlobalKey();
  final GlobalKey _stepperContentMeasureKey = GlobalKey();

  double? _headerHeight;
  double? _stepperHeight;
  double? _stepperContentWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMeasurements());
  }

  @override
  void didUpdateWidget(covariant EncounterJoinedHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMeasurements());
  }

  void _updateMeasurements() {
    final headerBox = _headerMeasureKey.currentContext?.findRenderObject() as RenderBox?;
    final stepperBox = _stepperMeasureKey.currentContext?.findRenderObject() as RenderBox?;
    final stepperContentBox = _stepperContentMeasureKey.currentContext?.findRenderObject() as RenderBox?;

    final nextHeaderHeight = headerBox?.size.height;
    final nextStepperHeight = stepperBox?.size.height;
    final nextStepperContentWidth = stepperContentBox?.size.width;

    if (nextHeaderHeight == _headerHeight &&
        nextStepperHeight == _stepperHeight &&
        nextStepperContentWidth == _stepperContentWidth) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _headerHeight = nextHeaderHeight;
      _stepperHeight = nextStepperHeight;
      _stepperContentWidth = nextStepperContentWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final mode = ref.watch(workspaceModeProvider);
    final showStepper = mode == WorkspaceMode.guided;
    final activePhase = ref.watch(encounterActivePhaseProvider(widget.visitId));
    final badges = ref.watch(encounterPhaseBadgesProvider(widget.visitId));
    final phaseNotifier = ref.read(encounterActivePhaseProvider(widget.visitId).notifier);
    final modeNotifier = ref.read(workspaceModeProvider.notifier);

    void selectPhase(EncounterPhase phase) {
      phaseNotifier.setPhase(phase);
      if (mode == WorkspaceMode.expert && phase.isDocumentation) {
        modeNotifier.setMode(WorkspaceMode.guided);
      }
    }

    final headerHeight = _headerHeight ?? 68.0;
    final stepperDepth = showStepper ? (_stepperHeight ?? kEncounterHeaderStepperMinDepth) : 0.0;
    final borderRadius = theme.tileRadius;
    final stepperWallInset = EncounterJoinedHeaderPath.resolvedWallInset(stepperDepth: stepperDepth);

    final stepperShelfPadding = stepperWallInset + SpacingTokens.sm;
    final dividerWidth = _stepperContentWidth == null
        ? null
        : _stepperContentWidth! * (1 + _dividerSideBleedFraction * 2);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: _headerMeasureKey,
          child: EncounterHeader(
            visit: widget.visit,
            onBack: widget.onBack,
            onEdit: widget.onEdit,
            beforeTrailing: widget.beforeTrailing,
            trailing: widget.trailing,
            decorated: false,
          ),
        ),
        if (showStepper)
          KeyedSubtree(
            key: _stepperMeasureKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: stepperShelfPadding),
                  child: Center(
                    child: dividerWidth == null
                        ? const SizedBox(height: 1)
                        : _FadingStepperShelfDivider(
                            width: dividerWidth,
                            color: theme.hairlineSoft,
                            sideBleedFraction: _dividerSideBleedFraction,
                          ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    stepperShelfPadding,
                    SpacingTokens.sm,
                    stepperShelfPadding,
                    SpacingTokens.sm,
                  ),
                  child: Center(
                    child: KeyedSubtree(
                      key: _stepperContentMeasureKey,
                      child: EncounterStepperHeader(
                        activePhase: activePhase,
                        badges: badges,
                        onPhaseSelected: selectPhase,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (!showStepper) {
      return Semantics(
        label: 'Encounter header',
        child: DecoratedBox(
          key: const Key('encounter_header'),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: theme.hairlineSoft),
          ),
          child: content,
        ),
      );
    }

    return Semantics(
      label: 'Encounter header with stepper',
      child: LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateMeasurements());

          return CustomPaint(
            foregroundPainter: EncounterJoinedHeaderBorderPainter(
              borderColor: theme.hairlineSoft,
              borderRadius: borderRadius,
              headerHeight: headerHeight,
              stepperDepth: stepperDepth,
              shoulderShelfSpan: widget.shoulderShelfSpan,
            ),
            child: ClipPath(
              clipper: EncounterJoinedHeaderClipper(
                borderRadius: borderRadius,
                headerHeight: headerHeight,
                stepperDepth: stepperDepth,
                shoulderShelfSpan: widget.shoulderShelfSpan,
              ),
              child: DecoratedBox(
                key: const Key('encounter_header'),
                decoration: BoxDecoration(color: theme.surface),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal shelf rule that fades out over the side bleed zones.
class _FadingStepperShelfDivider extends StatelessWidget {
  const _FadingStepperShelfDivider({required this.width, required this.color, required this.sideBleedFraction});

  final double width;
  final Color color;

  /// Fraction of the stepper width extending past each end (e.g. 0.1 = 10%).
  final double sideBleedFraction;

  @override
  Widget build(BuildContext context) {
    final fadeStop = sideBleedFraction / (1 + sideBleedFraction * 2);

    return SizedBox(
      width: width,
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color.withValues(alpha: 0), color, color, color.withValues(alpha: 0)],
            stops: [0, fadeStop, 1 - fadeStop, 1],
          ),
        ),
      ),
    );
  }
}
