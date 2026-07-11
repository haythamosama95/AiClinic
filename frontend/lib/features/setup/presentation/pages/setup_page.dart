import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_hydration_provider.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_wizard.dart';

class SetupPage extends ConsumerWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final wasLocked = previous?.context?.needsClinicSetup ?? false;
      final isLocked = next.context?.needsClinicSetup ?? false;
      if (!wasLocked || isLocked || !next.isAuthenticated) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        context.go(AppRoutes.home);
      });
    });

    final setupDone = ref.watch(isSetupCompleteProvider);
    final session = ref.watch(authSessionProvider).context;
    final setupRequired = session?.needsClinicSetup ?? false;
    final canRunBootstrapSetup = !setupRequired || (session?.canPerformBootstrapSetup ?? false);
    final colors = context.appColors;
    final hydration = ref.watch(clinicSetupHydrationProvider);

    final body = hydration.when(
      loading: () => _SetupHydrationLoading(colors: colors),
      error: (error, _) =>
          _SetupHydrationError(colors: colors, onRetry: () => ref.invalidate(clinicSetupHydrationProvider)),
      data: (_) => _SetupPageBody(
        setupDone: setupDone,
        canRunBootstrapSetup: canRunBootstrapSetup,
        colors: colors,
        onRunSetupAgain: () async {
          await ref.read(clinicSetupProvider.notifier).resetSetup();
          ref.invalidate(clinicSetupHydrationProvider);
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: body);
        }
        return body;
      },
    );
  }
}

class _SetupHydrationLoading extends StatelessWidget {
  const _SetupHydrationLoading({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Setup', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Walk through the essentials to get your clinic running — organization, branches, staff, and services.',
          style: AppTypography.body(context).copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        const Center(child: AppProgress(variant: ProgressVariant.circular, indeterminate: true)),
      ],
    );
  }
}

class _SetupHydrationError extends StatelessWidget {
  const _SetupHydrationError({required this.colors, required this.onRetry});

  final AppSemanticColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Setup', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Walk through the essentials to get your clinic running — organization, branches, staff, and services.',
          style: AppTypography.body(context).copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppAlert(
          variant: AppAlertVariant.danger,
          title: 'Unable to load clinic setup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Check your connection and try again.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space4),
              AppButton(variant: AppButtonVariant.secondary, onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupPageBody extends StatelessWidget {
  const _SetupPageBody({
    required this.setupDone,
    required this.canRunBootstrapSetup,
    required this.colors,
    required this.onRunSetupAgain,
  });

  final bool setupDone;
  final bool canRunBootstrapSetup;
  final AppSemanticColors colors;
  final Future<void> Function() onRunSetupAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Setup', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Walk through the essentials to get your clinic running — organization, branches, staff, and services.',
          style: AppTypography.body(context).copyWith(color: colors.textSecondary),
        ),
        if (setupDone) ...[
          const SizedBox(height: AppSpacing.space6),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColorPrimitives.teal300),
            ),
            child: AppCard(
              variant: CardVariant.raised,
              padding: CardPadding.lg,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColorPrimitives.teal50.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(color: AppColorPrimitives.teal50, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: const Icon(Icons.auto_fix_high, size: 18, color: AppColorPrimitives.teal700),
                            ),
                            const SizedBox(width: AppSpacing.space3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Setup complete',
                                    style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                                  ),
                                  Text(
                                    'Your clinic configuration is in place. Re-run the wizard to change defaults.',
                                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      AppButton(
                        variant: AppButtonVariant.secondary,
                        onPressed: () => onRunSetupAgain(),
                        child: const Text('Run setup again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        if (!setupDone && !canRunBootstrapSetup) ...[
          const SizedBox(height: AppSpacing.space6),
          AppAlert(
            variant: AppAlertVariant.warning,
            title: 'Administrator sign-in required',
            child: Text(
              'First-time clinic setup can only be completed by the clinic administrator account. '
              'Sign out and sign in with your administrator credentials to continue.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
          ),
        ],
        if (!setupDone && canRunBootstrapSetup) ...[const SizedBox(height: AppSpacing.space6), const SetupWizard()],
      ],
    );
  }
}
