import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';

/// Organization billing settings (V1-6 US8).
class BillingSettingsPage extends ConsumerWidget {
  const BillingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canManageBillingSettings()) {
      return const Scaffold(
        body: Center(
          child: AppEmptyState(
            variant: AppEmptyStateVariant.noAccess,
            title: 'Billing settings unavailable',
            description: 'You need permission to manage organization billing settings.',
          ),
        ),
      );
    }

    final settingsAsync = ref.watch(billingSettingsProvider);

    return Scaffold(
      body: AppScrollArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppPageHeader(
                title: 'Billing settings',
                description: 'Configure how payments and invoices behave for your organization.',
              ),
              const SizedBox(height: AppSpacing.space6),
              settingsAsync.when(
                loading: () => const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.space4),
                    child: AppSkeleton(height: 48),
                  ),
                ),
                error: (error, _) => AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: AppEmptyState(
                      variant: AppEmptyStateVariant.error,
                      title: 'Could not load billing settings',
                      description: error.toString(),
                      action: EmptyStateAction(
                        label: 'Retry',
                        onPressed: () => ref.read(billingSettingsProvider.notifier).reload(),
                      ),
                    ),
                  ),
                ),
                data: (settings) {
                  final isUpdating = settingsAsync.isLoading;
                  return AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: AppSpacing.space1,
                              children: [
                                Text('Allow partial payments', style: Theme.of(context).textTheme.titleSmall),
                                Text(
                                  'When enabled, staff can record patient payments below the full balance. '
                                  'When disabled, only the full remaining balance can be collected.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.appColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space4),
                          AppSwitch(
                            value: settings.allowPartialPayments,
                            disabled: isUpdating,
                            onChanged: (value) {
                              ref.read(billingSettingsProvider.notifier).updateAllowPartialPayments(value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
