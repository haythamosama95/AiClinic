import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Placeholder invoice detail page (V1-6 foundation).
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String? invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canView = permissions.canViewInvoices();

    if (!canView) {
      return const BillingAccessDeniedView(title: 'Invoice', message: 'You do not have permission to view invoices.');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(invoiceId == null ? 'Invoice' : 'Invoice $invoiceId'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: const Center(child: Text('Invoice detail will appear here.')),
    );
  }
}
