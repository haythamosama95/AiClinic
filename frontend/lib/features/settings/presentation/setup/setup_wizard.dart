import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_step_panel.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_step_rail.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/settings/presentation/setup/steps/branch_step.dart';
import 'package:ai_clinic/features/settings/presentation/setup/steps/organization_step.dart';
import 'package:ai_clinic/features/settings/presentation/setup/steps/services_step.dart';
import 'package:ai_clinic/features/settings/presentation/setup/steps/staff_step.dart';

const _stepCount = 4;
const _smBreakpoint = 600.0;

Map<String, String> _validateStep(int step, SetupDraft draft) {
  return switch (step) {
    0 => validateOrganization(draft.organization),
    1 => validateBranches(draft.branches),
    2 => validateStaff(draft.staff, draft.branches.length),
    3 => validateServices(draft.services),
    _ => const {},
  };
}

/// Setup wizard shell (web `SetupWizard`).
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  var _errors = <String, String>{};

  void _goNext() {
    final setupState = ref.read(clinicSetupDraftProvider);
    final step = setupState.step;
    final draft = setupState.draft;
    final stepErrors = _validateStep(step, draft);

    if (hasErrors(stepErrors)) {
      setState(() => _errors = stepErrors);
      return;
    }

    setState(() => _errors = {});

    final notifier = ref.read(clinicSetupDraftProvider.notifier);
    final isLastStep = step == _stepCount - 1;

    if (isLastStep) {
      notifier.completeSetup();
      return;
    }

    notifier.setStep(step + 1);
  }

  void _goBack() {
    final step = ref.read(clinicSetupDraftProvider).step;
    if (step == 0) return;

    setState(() => _errors = {});
    ref.read(clinicSetupDraftProvider.notifier).setStep(step - 1);
  }

  Widget _stepContent(int step) {
    return switch (step) {
      0 => OrganizationStep(errors: _errors),
      1 => BranchStep(errors: _errors),
      2 => StaffStep(errors: _errors),
      3 => ServicesStep(errors: _errors),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _stepPanel(int step, AppSemanticColors colors, bool isLastStep) {
    return SetupStepPanel(
      stepKey: '$step',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepContent(step),
          const SizedBox(height: AppSpacing.space10),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    disabled: step == 0,
                    onPressed: step == 0 ? null : _goBack,
                    leadingIcon: const Icon(Icons.arrow_back, size: 16),
                    child: const Text('Back'),
                  ),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    onPressed: _goNext,
                    trailingIcon: isLastStep ? null : const Icon(Icons.arrow_forward, size: 16),
                    child: Text(isLastStep ? 'Finish setup' : 'Continue'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(clinicSetupDraftProvider.select((state) => state.step));
    final progress = ((step + 1) / _stepCount) * 100;
    final isLastStep = step == _stepCount - 1;
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevationShadows.level1Light,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Stack(
          children: [
            const Positioned.fill(child: _BlueprintGridBackdrop()),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.borderSubtle)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.space6,
                      AppSpacing.space5,
                      AppSpacing.space6,
                      AppSpacing.space5,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.auto_fix_high, size: 18, color: AppColorPrimitives.teal600),
                              const SizedBox(width: AppSpacing.space2),
                              Text(
                                'Clinic setup',
                                style: AppTypography.h3(
                                  context,
                                ).copyWith(color: AppColorPrimitives.teal600, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Step ${step + 1} of $_stepCount',
                                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.space2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: AppProgress(variant: ProgressVariant.bar, value: progress, showLabel: false),
                                  ),
                                  const SizedBox(width: AppSpacing.space2),
                                  Text(
                                    '${progress.round()}%',
                                    style: AppTypography.caption(context).copyWith(
                                      color: colors.textTertiary,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final showRail = constraints.maxWidth >= _smBreakpoint;
                      final body = _stepPanel(step, colors, isLastStep);

                      if (!showRail) {
                        return body;
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 208, child: SetupStepRail(currentStep: step)),
                          const SizedBox(width: AppSpacing.space8),
                          Expanded(child: body),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlueprintGridBackdrop extends StatelessWidget {
  const _BlueprintGridBackdrop();

  static const _gridSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          return const RadialGradient(
            center: Alignment(0, -1),
            radius: 1.2,
            colors: [Color(0xFF000000), Color(0x33000000), Color(0x00000000)],
            stops: [0.2, 0.5, 0.7],
          ).createShader(bounds);
        },
        child: Opacity(
          opacity: 0.35,
          child: CustomPaint(
            painter: _BlueprintGridPainter(color: colors.borderSubtle),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _BlueprintGridPainter extends CustomPainter {
  const _BlueprintGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += _BlueprintGridBackdrop._gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += _BlueprintGridBackdrop._gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
