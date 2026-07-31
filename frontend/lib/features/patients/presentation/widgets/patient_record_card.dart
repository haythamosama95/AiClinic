import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Raised teal-tinted record card shell (web `RecordCardShell`).
class PatientRecordCard extends StatefulWidget {
  const PatientRecordCard({
    required this.child,
    this.leading,
    this.useNeutralGradient = false,
    this.compact = false,
    super.key,
  });

  final Widget child;
  final Widget? leading;

  /// Muted gradient for document cards (Phase 3); default is teal-tinted.
  final bool useNeutralGradient;

  /// When true, the card height follows its content instead of the default minimum.
  final bool compact;

  static const _leadingWidth = 84.0; // 5.25rem
  static const _minHeight = 152.0; // 9.5rem

  @override
  State<PatientRecordCard> createState() => _PatientRecordCardState();
}

class _PatientRecordCardState extends State<PatientRecordCard> {
  var _hovered = false;

  /// Theme-aware teal accent mix (`surfaceSelected` is teal-tinted in both modes).
  Color _accentMix(AppSemanticColors colors, double amount) {
    return Color.lerp(colors.surfaceDefault, colors.surfaceSelected, amount)!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final translateY = _hovered && !reducedMotion ? -2.0 : 0.0;
    final borderColor = _hovered ? colors.borderDefault : colors.borderSubtle;
    final shadows = _hovered
        ? elevation.shadowsFor(2)
        : elevation.shadowsFor(1);

    final gradientEnd = widget.useNeutralGradient
        ? Color.lerp(colors.surfaceDefault, colors.surfaceMuted, 0.55)!
        : _accentMix(colors, 0.28);

    final leadingGradientTop = widget.useNeutralGradient
        ? colors.surfaceMuted
        : _accentMix(colors, 0.55);
    final leadingGradientBottom = widget.useNeutralGradient
        ? colors.surfaceSunken
        : _accentMix(colors, 0.80);

    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: reducedMotion ? Duration.zero : AppMotion.base,
          curve: AppMotion.standardCurve,
          transform: Matrix4.translationValues(0, translateY, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            border: Border.all(color: borderColor),
            boxShadow: shadows,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: const Alignment(-0.4, 1),
              colors: [colors.surfaceDefault, gradientEnd],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            child: ConstrainedBox(
              constraints: widget.compact
                  ? const BoxConstraints()
                  : const BoxConstraints(
                      minHeight: PatientRecordCard._minHeight,
                    ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.leading != null)
                      _buildLeadingColumn(
                        colors,
                        leadingGradientTop,
                        leadingGradientBottom,
                        widget.leading!,
                      ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingColumn(
    AppSemanticColors colors,
    Color gradientTop,
    Color gradientBottom,
    Widget leading,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(end: BorderSide(color: colors.borderSubtle)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradientTop, gradientBottom],
        ),
      ),
      child: SizedBox(
        width: PatientRecordCard._leadingWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space2,
            vertical: AppSpacing.space5,
          ),
          child: Center(child: ExcludeSemantics(child: leading)),
        ),
      ),
    );
  }
}
