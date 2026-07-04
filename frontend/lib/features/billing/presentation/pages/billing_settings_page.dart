import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_action_button.dart';

/// Organization billing settings (V1-6 US8).
class BillingSettingsPage extends ConsumerWidget {
  const BillingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessBillingSettings(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Billing settings',
        description: 'You do not have permission to view billing settings.',
      );
    }

    final canManage = ref.watch(permissionServiceProvider).canManageBillingSettings();
    final settingsAsync = ref.watch(billingSettingsProvider);

    return settingsAsync.when(
      loading: () => EditorFormPattern(
        title: 'Billing settings',
        description: 'Configure organization-wide billing policies.',
        sections: const [
          EditorFormSection(
            title: 'Payments',
            fields: [Center(child: AppSpinner())],
          ),
        ],
        footer: const SizedBox.shrink(),
      ),
      error: (error, _) => EditorFormPattern(
        title: 'Billing settings',
        sections: [
          EditorFormSection(
            title: 'Payments',
            fields: [
              AppErrorState(
                message: error is RpcFailure ? billingMessageForRpc(error) : error.toString(),
                onRetry: () => ref.read(billingSettingsProvider.notifier).reload(),
              ),
            ],
          ),
        ],
        footer: const SizedBox.shrink(),
      ),
      data: (settings) => EditorFormPattern(
        title: 'Billing settings',
        description: 'Configure organization-wide billing policies.',
        sections: [
          EditorFormSection(
            title: 'Payments',
            description: 'Organization-wide billing policies apply to all branches.',
            fields: [
              Text(
                'When disabled, patient-tender payments must equal the full invoice balance.',
                style: context.typography.bodySm.copyWith(color: context.colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s3),
              BillingActionButton(
                disabledReason: canManage
                    ? null
                    : 'Only clinic owners and administrators can change this setting.',
                child: AppSwitch(
                  key: const Key('billing_allow_partial_payments_toggle'),
                  label: 'Allow partial payments',
                  value: settings.allowPartialPayments,
                  disabled: !canManage,
                  onChanged: canManage
                      ? (value) async {
                          try {
                            await ref
                                .read(billingSettingsProvider.notifier)
                                .updateAllowPartialPayments(value);
                            ref.showAppToast(
                              message: 'Billing settings updated.',
                              variant: AppToastVariant.success,
                            );
                          } on RpcFailure catch (error) {
                            ref.showAppToast(
                              message: billingMessageForRpc(error),
                              variant: AppToastVariant.danger,
                            );
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
        footer: const SizedBox.shrink(),
      ),
    );
  }
}
