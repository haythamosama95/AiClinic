import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

final visitInvoiceProvider = FutureProvider.autoDispose.family<InvoiceListItem?, String>((ref, visitId) async {
  return ref.watch(invoiceRepositoryProvider).findForVisit(visitId: visitId);
});

/// Create or open invoice actions for completed visits (V1-6 US1).
class VisitDetailActions extends ConsumerWidget {
  const VisitDetailActions({super.key, required this.visitId, required this.status});

  final String visitId;
  final VisitStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (status != VisitStatus.completed) {
      return const SizedBox.shrink();
    }

    final canCreate = ref.watch(permissionServiceProvider).canCreateInvoices();
    if (!canCreate) {
      return const SizedBox.shrink();
    }

    final invoiceAsync = ref.watch(visitInvoiceProvider(visitId));

    return invoiceAsync.when(
      loading: () => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, _) => const SizedBox.shrink(),
      data: (invoice) {
        if (invoice == null) {
          return TextButton.icon(
            key: const Key('visit_create_invoice_button'),
            onPressed: () => _createInvoice(context, ref),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Create invoice'),
          );
        }

        return TextButton.icon(
          key: const Key('visit_open_invoice_button'),
          onPressed: () => _openInvoice(context, invoice),
          icon: const Icon(Icons.open_in_new),
          label: Text(invoice.status == InvoiceStatus.draft ? 'Open draft invoice' : 'Open invoice'),
        );
      },
    );
  }

  Future<void> _createInvoice(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invoiceId = await ref.read(invoiceRepositoryProvider).createFromVisit(visitId: visitId);
      ref.invalidate(visitInvoiceProvider(visitId));
      if (!context.mounted) {
        return;
      }
      context.push(AppRoutes.billingInvoiceEdit(invoiceId));
    } on RpcFailure catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(billingMessageForRpc(error))));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openInvoice(BuildContext context, InvoiceListItem invoice) {
    if (invoice.status == InvoiceStatus.draft) {
      context.push(AppRoutes.billingInvoiceEdit(invoice.id));
      return;
    }
    context.push(AppRoutes.billingInvoiceDetail(invoice.id));
  }
}
