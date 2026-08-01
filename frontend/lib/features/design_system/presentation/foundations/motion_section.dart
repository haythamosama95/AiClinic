import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_elevation.dart' show AppElevationContext;
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'foundation_constants.dart';
import 'foundation_section.dart';

/// Motion playground with preset chips, replay demo, and staggered rows.
class MotionSection extends StatefulWidget {
  const MotionSection({super.key});

  @override
  State<MotionSection> createState() => _MotionSectionState();
}

class _MotionSectionState extends State<MotionSection> with TickerProviderStateMixin {
  AppMotionPreset _activePreset = AppMotionPreset.fadeScale;
  late AnimationController _demoController;
  late AnimationController _staggerController;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _demoController = AnimationController(vsync: this, duration: AppMotionDuration.base);
    _staggerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _replay();
    }
  }

  @override
  void dispose() {
    _demoController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _replay() {
    final transition = AppMotion.transitionFor(context: context, preset: _activePreset);
    _demoController.duration = transition.duration;
    _demoController
      ..reset()
      ..forward();

    _staggerController
      ..reset()
      ..forward();
  }

  void _selectPreset(AppMotionPreset preset) {
    setState(() => _activePreset = preset);
    _replay();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final transition = AppMotion.transitionFor(context: context, preset: _activePreset);

    return FoundationSection(
      id: 'motion',
      title: 'Motion',
      description: 'Presets from 03-motion. Respects prefers-reduced-motion.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final preset in motionPresetList)
                _PresetChip(
                  label: 'motion-${motionPresetLabel(preset)}',
                  selected: _activePreset == preset,
                  onTap: () => _selectPreset(preset),
                ),
              _ReplayChip(onTap: _replay),
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
          Container(
            height: 192,
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
            ),
            child: AnimatedBuilder(
              animation: _demoController,
              builder: (context, child) {
                final t = reducedMotion
                    ? 1.0
                    : CurvedAnimation(parent: _demoController, curve: transition.curve).value;
                final values = AppMotion.lerpPreset(
                  preset: _activePreset,
                  t: t,
                  direction: Directionality.of(context),
                );
                return Opacity(
                  opacity: values.opacity,
                  child: Transform.translate(
                    offset: values.offset,
                    child: Transform.scale(
                      scale: values.scale,
                      child: child,
                    ),
                  ),
                );
              },
              child: Container(
                width: 192,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceDefault,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: context.appElevation.shadowsFor(2),
                ),
                child: Text(
                  motionPresetLabel(_activePreset),
                  style: AppTypography.bodyStrong(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          Text('Staggered row enter (≤5)', style: AppTypography.overline(context)),
          const SizedBox(height: AppSpacing.space3),
          Column(
            children: [
              for (var index = 0; index < 5; index++)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.space2),
                  child: AnimatedBuilder(
                    animation: _staggerController,
                    builder: (context, child) {
                      final start = index * 0.12;
                      final end = (start + 0.55).clamp(0.0, 1.0);
                      final t = reducedMotion
                          ? 1.0
                          : Interval(start, end, curve: AppMotionEasing.out).transform(_staggerController.value);
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, 6 * (1 - t)),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space4,
                        vertical: AppSpacing.space2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceDefault,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        'Row ${index + 1}',
                        style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: selected ? colors.surfaceSelected : colors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
          child: Text(
            label,
            style: AppTypography.bodySm(context).copyWith(
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayChip extends StatelessWidget {
  const _ReplayChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.borderDefault),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
          child: Text('Replay', style: AppTypography.bodySm(context)),
        ),
      ),
    );
  }
}
