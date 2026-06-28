import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
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
      loading: () => const SizedBox(width: 24, height: 24, child: AppCircularProgress()),
      error: (_, _) => const SizedBox.shrink(),
      data: (invoice) {
        if (invoice == null) {
          return AppButton(
            key: const Key('visit_create_invoice_button'),
            label: 'Create invoice',
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            onPressed: () => _createInvoice(context, ref),
          );
        }

        return AppButton(
          key: const Key('visit_open_invoice_button'),
          label: invoice.status == InvoiceStatus.draft ? 'Open draft invoice' : 'Open invoice',
          variant: AppButtonVariant.outline,
          icon: const Icon(Icons.open_in_new, size: 18),
          onPressed: () => _openInvoice(context, invoice),
        );
      },
    );
  }

  Future<void> _createInvoice(BuildContext context, WidgetRef ref) async {
    try {
      final invoiceId = await ref.read(invoiceRepositoryProvider).createFromVisit(visitId: visitId);
      ref.invalidate(visitInvoiceProvider(visitId));
      if (!context.mounted) {
        return;
      }
      context.push(AppRoutes.billingInvoiceEdit(invoiceId));
    } on RpcFailure catch (error) {
      if (!context.mounted) {
        return;
      }
      AppToast.error(context, message: billingMessageForRpc(error));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppToast.error(context, message: error.toString());
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
