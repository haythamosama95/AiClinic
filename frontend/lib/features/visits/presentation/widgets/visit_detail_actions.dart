import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

final visitInvoiceProvider = FutureProvider.autoDispose.family<InvoiceListItem?, String>((ref, visitId) async {
  return ref.watch(invoiceRepositoryProvider).findForVisit(visitId: visitId);
});

/// Invoice and documentation actions for visit detail and documentation screens (013 US6).
class VisitDetailActions extends ConsumerWidget {
  const VisitDetailActions({super.key, required this.visitId, required this.status, this.canEditDocumentation = false});

  final String visitId;
  final VisitStatus status;
  final bool canEditDocumentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[];

    if (canEditDocumentation) {
      children.add(
        AppButton(
          key: const Key('visit_detail_edit_documentation'),
          label: status == VisitStatus.inProgress ? 'Edit documentation' : 'Edit visit',
          variant: AppButtonVariant.outline,
          icon: const Icon(Icons.edit_note_outlined, size: 18),
          onPressed: () =>
              context.push(AppRoutes.visitDocument(visitId, startEditing: status == VisitStatus.completed)),
        ),
      );
    }

    if (status == VisitStatus.completed) {
      final invoiceAction = _buildInvoiceAction(context, ref);
      if (invoiceAction != null) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(width: SpacingTokens.sm));
        }
        children.add(invoiceAction);
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget? _buildInvoiceAction(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(permissionServiceProvider).canCreateInvoices();
    if (!canCreate) {
      return null;
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
