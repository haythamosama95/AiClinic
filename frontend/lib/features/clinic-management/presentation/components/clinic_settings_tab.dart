import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/clinic_tab_header.dart';

/// Organization billing settings tab (web `ClinicSettingsTab`).
class ClinicSettingsTab extends ConsumerWidget {
  const ClinicSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(billingSettingsProvider);

    return settingsState.when(
      data: (settings) {
        final colors = context.appColors;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ClinicTabHeader(
              title: 'Clinic settings',
              description: 'Organization-wide billing and invoicing behavior for all branches.',
            ),
            const SizedBox(height: AppSpacing.space6),
            AppCard(
              variant: CardVariant.raised,
              padding: CardPadding.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.credit_card_outlined, size: 20, color: colors.iconMuted),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Billing', style: AppTypography.bodyStrong(context)),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              'Control how patient payments are recorded against invoices.',
                              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final switchControl = Semantics(
                            label: 'Allow partial payments',
                            child: AppSwitch(
                              value: settings.allowPartialPayments,
                              onChanged: (value) =>
                                  ref.read(billingSettingsProvider.notifier).updateAllowPartialPayments(value),
                            ),
                          );

                          final description = Text(
                            'When enabled, staff can record payments that do not cover the full invoice balance. '
                            'When disabled, each payment must settle the remaining amount in full.',
                            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                          );

                          if (constraints.maxWidth >= 480) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Allow partial payments', style: AppTypography.bodyStrong(context)),
                                      const SizedBox(height: AppSpacing.space1),
                                      description,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.space4),
                                switchControl,
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Allow partial payments', style: AppTypography.bodyStrong(context)),
                              const SizedBox(height: AppSpacing.space1),
                              description,
                              const SizedBox(height: AppSpacing.space4),
                              Align(alignment: AlignmentDirectional.centerStart, child: switchControl),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AppEmptyState(variant: AppEmptyStateVariant.error),
    );
  }
}
