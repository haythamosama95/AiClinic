import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Placeholder invoice list page (V1-6 foundation).
class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canView = permissions.canViewInvoices();

    if (!canView) {
      return const BillingAccessDeniedView(title: 'Invoices', message: 'You do not have permission to view invoices.');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: const Center(child: Text('Invoice list will appear here.')),
    );
  }
}
