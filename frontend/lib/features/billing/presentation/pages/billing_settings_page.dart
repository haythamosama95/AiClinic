import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/billing_settings_section.dart';

/// Organization billing settings (V1-6 US8).
class BillingSettingsPage extends ConsumerWidget {
  const BillingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canAccess = permissions.canViewInvoices() || permissions.canRecordPayment();

    if (!canAccess) {
      return const BillingAccessDeniedView(
        title: 'Billing settings',
        message: 'You do not have permission to view billing settings.',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing settings'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goSettings(),
        ),
      ),
      body: const SingleChildScrollView(padding: EdgeInsets.all(24), child: BillingSettingsSection()),
    );
  }
}
