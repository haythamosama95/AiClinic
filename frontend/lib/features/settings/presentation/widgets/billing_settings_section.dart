import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';

/// Organization-level billing toggles (V1-6 US8).
class BillingSettingsSection extends ConsumerStatefulWidget {
  const BillingSettingsSection({super.key});

  @override
  ConsumerState<BillingSettingsSection> createState() => _BillingSettingsSectionState();
}

class _BillingSettingsSectionState extends ConsumerState<BillingSettingsSection> {
  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final canView = permissions.canViewInvoices() || permissions.canRecordPayment();
    if (!canView) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(billingSettingsProvider);

    ref.listen<AsyncValue<BillingSettingsUiState>>(billingSettingsProvider, (previous, next) {
      final value = next.value;
      if (value?.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.successMessage!)));
        ref.read(billingSettingsProvider.notifier).clearMessages();
      } else if (value?.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(value!.errorMessage!), backgroundColor: Theme.of(context).colorScheme.error),
        );
        ref.read(billingSettingsProvider.notifier).clearMessages();
      }
    });

    return settingsAsync.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
      error: (error, _) => Text('Failed to load billing settings: $error'),
      data: (ui) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Billing', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('billing_allow_partial_payments_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow partial payments'),
              subtitle: Text(
                ui.canEdit
                    ? 'When disabled, patient-tender payments must equal the full invoice balance.'
                    : 'Only clinic owners and administrators can change this setting.',
              ),
              value: ui.settings.allowPartialPayments,
              onChanged: ui.canEdit && !ui.isSaving
                  ? (value) => ref.read(billingSettingsProvider.notifier).updateAllowPartialPayments(value)
                  : null,
            ),
            if (ui.isSaving) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator()),
          ],
        );
      },
    );
  }
}
