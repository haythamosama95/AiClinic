import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Loads the active invoice for a visit when the user can view invoices.
final visitInvoiceProvider = FutureProvider.autoDispose.family<InvoiceListItem?, String>((ref, visitId) async {
  final permissions = ref.watch(permissionServiceProvider);
  if (!permissions.canViewInvoices()) {
    return null;
  }

  return ref.read(invoiceRepositoryProvider).findForVisit(visitId: visitId);
});

/// Invoice and documentation actions for visit detail and documentation screens (013 US6).
class VisitDetailActions extends ConsumerStatefulWidget {
  const VisitDetailActions({super.key, required this.visitId, required this.status, this.canEditDocumentation = false});

  final String visitId;
  final VisitStatus status;
  final bool canEditDocumentation;

  @override
  ConsumerState<VisitDetailActions> createState() => _VisitDetailActionsState();
}

class _VisitDetailActionsState extends ConsumerState<VisitDetailActions> {
  var _isCreatingInvoice = false;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (widget.canEditDocumentation) {
      children.add(
        AppButton(
          key: const Key('visit_detail_edit_documentation'),
          label: widget.status == VisitStatus.inProgress ? 'Edit documentation' : 'Edit visit',
          variant: AppButtonVariant.outline,
          icon: const Icon(Icons.edit_note_outlined, size: 18),
          onPressed: () => context.push(
            AppRoutes.visitDocument(widget.visitId, startEditing: widget.status == VisitStatus.completed),
          ),
        ),
      );
    }

    if (widget.status == VisitStatus.completed) {
      final invoiceAction = _buildInvoiceAction(context);
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

  Widget? _buildInvoiceAction(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final canCreate = permissions.canCreateInvoices();
    final canView = permissions.canViewInvoices();

    if (!canCreate && !canView) {
      return null;
    }

    if (!canView) {
      return AppButton(
        key: const Key('visit_create_invoice_button'),
        label: 'Create invoice',
        variant: AppButtonVariant.outline,
        icon: const Icon(Icons.receipt_long_outlined, size: 18),
        isLoading: _isCreatingInvoice,
        onPressed: _isCreatingInvoice ? null : () => _createInvoice(context),
      );
    }

    final invoiceAsync = ref.watch(visitInvoiceProvider(widget.visitId));

    return invoiceAsync.when(
      loading: () => const SizedBox(width: 24, height: 24, child: AppCircularProgress()),
      error: (_, _) {
        if (!canCreate) {
          return null;
        }
        return AppButton(
          key: const Key('visit_create_invoice_button'),
          label: 'Create invoice',
          variant: AppButtonVariant.outline,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          isLoading: _isCreatingInvoice,
          onPressed: _isCreatingInvoice ? null : () => _createInvoice(context),
        );
      },
      data: (invoice) {
        if (invoice == null) {
          if (!canCreate) {
            return null;
          }
          return AppButton(
            key: const Key('visit_create_invoice_button'),
            label: 'Create invoice',
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            isLoading: _isCreatingInvoice,
            onPressed: _isCreatingInvoice ? null : () => _createInvoice(context),
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

  Future<void> _createInvoice(BuildContext context) async {
    setState(() => _isCreatingInvoice = true);
    try {
      final invoiceId = await ref.read(invoiceRepositoryProvider).createFromVisit(visitId: widget.visitId);
      ref.invalidate(visitInvoiceProvider(widget.visitId));
      if (!context.mounted) {
        return;
      }
      AppNavigator(context).pushBillingInvoiceEdit(invoiceId);
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
    } finally {
      if (mounted) {
        setState(() => _isCreatingInvoice = false);
      }
    }
  }

  void _openInvoice(BuildContext context, InvoiceListItem invoice) {
    final navigator = AppNavigator(context);
    if (invoice.status == InvoiceStatus.draft) {
      navigator.pushBillingInvoiceEdit(invoice.id);
      return;
    }
    navigator.pushBillingInvoiceDetail(invoice.id);
  }
}

/// Prominent billing CTA shown on the completed-visit review canvas (V1-6 US1).
class VisitBillingPromptCard extends ConsumerWidget {
  const VisitBillingPromptCard({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canViewInvoices() && !permissions.canCreateInvoices()) {
      return const SizedBox.shrink();
    }

    return AppCard(
      title: const Text('Billing'),
      description: const Text('Issue an invoice for services documented in this visit.'),
      child: VisitDetailActions(visitId: visitId, status: VisitStatus.completed),
    );
  }
}
