import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/components/app_stepper.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_step_panel.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/branch_step.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/organization_step.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/services_step.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/staff_step.dart';

const _smBreakpoint = 600.0;

const _allSetupSteps = <AppStep>[
  AppStep(id: 'organization', label: 'Organization', description: 'Name & region'),
  AppStep(id: 'branch', label: 'Branch', description: 'Locations & hours'),
  AppStep(id: 'staff', label: 'Staff', description: 'Team & access'),
  AppStep(id: 'services', label: 'Services', description: 'Catalog & pricing'),
];

const _bootstrapSetupSteps = <AppStep>[
  AppStep(id: 'organization', label: 'Organization', description: 'Name & region'),
  AppStep(id: 'branch', label: 'Branch', description: 'Your first location'),
  AppStep(id: 'staff', label: 'Staff', description: 'Team & access'),
];

/// Setup wizard shell (web `SetupWizard`).
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({this.embedded = false, super.key});

  /// When true, omits outer card chrome so the wizard header sits flush inside a dialog shell.
  final bool embedded;

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  var _errors = <String, String>{};
  final _branchStepKey = GlobalKey();
  final _staffStepKey = GlobalKey();

  Future<void> _goNext() async {
    final setupState = ref.read(clinicSetupProvider);
    final bootstrapMode = ref.read(authSessionProvider).context?.needsClinicSetup ?? false;
    final stepCount = setupWizardStepCount(bootstrapMode: bootstrapMode);
    final step = setupState.step;
    final draft = setupState.draft;
    final stepErrors = validateStep(step, draft, bootstrapMode: bootstrapMode);

    if (hasErrors(stepErrors)) {
      final notifier = ref.read(clinicSetupProvider.notifier);
      switch (step) {
        case 1:
          notifier.revealBranchValidationErrors(stepErrors);
        case 2:
          notifier.revealStaffValidationErrors(stepErrors);
        case 3:
          notifier.revealServiceValidationErrors(stepErrors);
      }
      setState(() => _errors = stepErrors);
      return;
    }

    setState(() => _errors = {});

    final notifier = ref.read(clinicSetupProvider.notifier);
    final isLastStep = step == stepCount - 1;

    await notifier.persistDraft();

    if (isLastStep) {
      final ok = await notifier.completeSetup();
      if (!ok && mounted) {
        setState(() {});
      }
      return;
    }

    notifier.markStepComplete(step);
    notifier.setStep(step + 1);
  }

  void _goBack() {
    final step = ref.read(clinicSetupProvider).step;
    if (step == 0) return;

    setState(() => _errors = {});
    ref.read(clinicSetupProvider.notifier).setStep(step - 1);
  }

  Widget _stepContent(int step, {required bool bootstrapMode}) {
    return switch (step) {
      0 => OrganizationStep(errors: _errors),
      1 => BranchStep(key: _branchStepKey, errors: _errors, bootstrapMode: bootstrapMode),
      2 => StaffStep(key: _staffStepKey, errors: _errors, bootstrapMode: bootstrapMode),
      3 when !bootstrapMode => ServicesStep(errors: _errors),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _stepPanel(
    int step,
    AppSemanticColors colors,
    bool isLastStep,
    bool isSubmitting,
    String? submitError, {
    required bool bootstrapMode,
  }) {
    return SetupStepPanel(
      stepKey: '$step',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepContent(step, bootstrapMode: bootstrapMode),
          if (submitError != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Semantics(
              liveRegion: true,
              child: Text(submitError, style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg)),
            ),
          ],
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
                    disabled: step == 0 || isSubmitting,
                    onPressed: step == 0 || isSubmitting ? null : _goBack,
                    leadingIcon: const Icon(Icons.arrow_back, size: 16),
                    child: const Text('Back'),
                  ),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    disabled: isSubmitting,
                    onPressed: isSubmitting ? null : _goNext,
                    trailingIcon: isLastStep || isSubmitting ? null : const Icon(Icons.arrow_forward, size: 16),
                    child: Text(isLastStep ? (isSubmitting ? 'Finishing setup…' : 'Finish setup') : 'Continue'),
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
    final setupState = ref.watch(clinicSetupProvider);
    final bootstrapMode = ref.watch(authSessionProvider.select((auth) => auth.context?.needsClinicSetup ?? false));
    final stepCount = setupWizardStepCount(bootstrapMode: bootstrapMode);
    final step = setupState.step.clamp(0, stepCount - 1);

    if (bootstrapMode && setupState.step >= stepCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(clinicSetupProvider.notifier).setStep(stepCount - 1);
      });
    }

    final progress = ((step + 1) / stepCount) * 100;
    final isLastStep = step == stepCount - 1;
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    final content = Stack(
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
                            'Step ${step + 1} of $stepCount',
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
                  final body = _stepPanel(
                    step,
                    colors,
                    isLastStep,
                    setupState.isSubmitting,
                    setupState.submitError,
                    bootstrapMode: bootstrapMode,
                  );

                  if (!showRail) {
                    return body;
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 208,
                        child: AppStepper(
                          orientation: AppStepperOrientation.vertical,
                          steps: bootstrapMode ? _bootstrapSetupSteps : _allSetupSteps,
                          currentStep: step,
                        ),
                      ),
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
    );

    if (widget.embedded) {
      return ColoredBox(color: colors.surfaceDefault, child: content);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevationShadows.level1Light,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.x2l), child: content),
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
