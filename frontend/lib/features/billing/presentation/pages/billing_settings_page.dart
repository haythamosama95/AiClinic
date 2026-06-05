import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Placeholder billing settings page (V1-6 foundation).
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
      body: const Center(child: Text('Billing settings will appear here.')),
    );
  }
}
