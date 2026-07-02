import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

/// Organization billing settings: partial payments toggle (V1-6 US8).
class BillingSettingsSection extends ConsumerWidget {
  const BillingSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessBillingSettings(auth)) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(billingSettingsProvider);
    final canEdit = ref.watch(permissionServiceProvider).canManageBillingSettings();

    return settingsAsync.when(
      loading: () => const SettingsSectionCard(
        title: 'Billing',
        child: Center(child: AppCircularProgress()),
      ),
      error: (error, _) =>
          SettingsSectionCard(title: 'Billing', child: Text('Unable to load billing settings: $error')),
      data: (settings) => SettingsSectionCard(
        title: 'Billing',
        child: SettingsField(
          label: 'Allow partial payments',
          description: canEdit
              ? 'When disabled, patient-tender payments must equal the full balance.'
              : 'Only administrators can change this setting. Current value applies to all branches.',
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(settings.allowPartialPayments ? 'Enabled' : 'Disabled'),
            subtitle: Text(
              settings.allowPartialPayments
                  ? 'Staff may record payments less than the full balance.'
                  : 'Staff must collect the full balance for cash, card, and bank transfer.',
            ),
            value: settings.allowPartialPayments,
            onChanged: canEdit ? (value) => _update(context, ref, value) : null,
          ),
        ),
      ),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, bool value) async {
    try {
      await ref.read(billingSettingsProvider.notifier).updateAllowPartialPayments(value);
      if (context.mounted) {
        AppToast.success(context, message: 'Billing settings updated.');
      }
    } on RpcFailure catch (error) {
      if (context.mounted) {
        AppToast.error(context, message: billingMessageForRpc(error));
      }
    }
  }
}

/// Standalone page for `/settings/billing` route.
class BillingSettingsPage extends ConsumerWidget {
  const BillingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(SpacingTokens.lg), children: const [BillingSettingsSection()]);
  }
}
