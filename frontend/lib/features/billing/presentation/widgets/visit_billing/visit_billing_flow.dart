import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
<<<<<<< HEAD
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
=======
>>>>>>> master
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_dialog.dart';

/// Post-review billing workflow (web `VisitBillingFlow`).
class VisitBillingFlow extends ConsumerStatefulWidget {
  const VisitBillingFlow({
    required this.visitId,
    this.onBackToReview,
    this.onCompleted,
    super.key,
  });

  final String visitId;
  final VoidCallback? onBackToReview;
  final VoidCallback? onCompleted;

  @override
  ConsumerState<VisitBillingFlow> createState() => _VisitBillingFlowState();
}

class _VisitBillingFlowState extends ConsumerState<VisitBillingFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _enterAnimation;

  @override
  void initState() {
    super.initState();
    final reducedMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _enterController = AnimationController(
      vsync: this,
      duration: reducedMotion ? Duration.zero : AppMotionDuration.base,
    );
    _enterAnimation = CurvedAnimation(
      parent: _enterController,
      curve: AppMotion.outCurve,
    );
    _enterController.forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  void _handleBackToReview() {
    ref.read(visitBillingFlowProvider(widget.visitId).notifier).reset();
    widget.onBackToReview?.call();
  }

  Future<void> _handleFinalize() async {
    final billing = ref.read(visitBillingFlowProvider(widget.visitId));
    if (billing.isSubmitting || billing.selectedLines.isEmpty) {
      return;
    }

    final permissions = ref.read(permissionServiceProvider);
    final billingNotifier = ref.read(
      visitBillingFlowProvider(widget.visitId).notifier,
    );
    billingNotifier.setSubmitting(true);

    try {
      final docNotifier = ref.read(
        visitDocumentationProvider(widget.visitId).notifier,
      );
      await docNotifier.completeVisit();

      InvoiceDetail? invoice;
      if (permissions.canCreateInvoices()) {
        try {
          invoice = await _createAndIssueInvoice(
            visitId: widget.visitId,
            lines: billing.selectedLines,
            discountType: billing.discountType,
            discountValue: billing.discountValue,
            canApplyDiscount: permissions.canApplyDiscount(),
          );
        } on RpcFailure catch (error) {
          if (!mounted) {
            return;
          }
          _showError(billingMessageForRpc(error));
          return;
        }
      }

      if (!mounted) {
        return;
      }

      final completedVisit = ref
          .read(visitDocumentationProvider(widget.visitId))
          .value
          ?.visit;
      if (completedVisit == null) {
        _showError('Could not finalize the visit. Please try again.');
        return;
      }

      final invoicePreview = billing.invoicePreview;
      billingNotifier.reset();
      await VisitSubmittedDialog.show(
        context,
        ref,
        visit: completedVisit,
        actionAt: DateTime.now().toUtc(),
        invoicePreview: invoicePreview,
        persistedInvoice: invoice,
      );
      if (mounted) {
        widget.onCompleted?.call();
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      _showError(visitMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError('Could not finalize the visit. Please try again.');
    } finally {
      billingNotifier.setSubmitting(false);
    }
  }

  Future<InvoiceDetail?> _createAndIssueInvoice({
    required String visitId,
    required List<VisitSelectedServiceLine> lines,
    required VisitBillingDiscountType discountType,
    required double discountValue,
    required bool canApplyDiscount,
  }) async {
    final invoiceRepo = ref.read(invoiceRepositoryProvider);
    final catalogRepo = ref.read(serviceCatalogRepositoryProvider);

    final invoiceId = await invoiceRepo.createFromVisit(visitId: visitId);
    var invoice = await invoiceRepo.getDetail(invoiceId: invoiceId);

    for (final line in lines) {
      final result = await catalogRepo.addInvoiceItemFromService(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        serviceId: line.serviceId,
      );

      invoice = await invoiceRepo.getDetail(invoiceId: invoiceId);

      if (line.quantity > 1) {
        final item = invoice.items.firstWhere(
          (entry) => entry.id == result.itemId,
        );
        await invoiceRepo.updateItem(
          itemId: result.itemId,
          expectedUpdatedAt: invoice.updatedAt,
          description: item.description,
          quantity: line.quantity.toString(),
          unitPrice: item.unitPrice.wireValue,
        );
        invoice = await invoiceRepo.getDetail(invoiceId: invoiceId);
      }
    }

    if (canApplyDiscount &&
        discountType != VisitBillingDiscountType.none &&
        discountValue > 0) {
      final kind = switch (discountType) {
        VisitBillingDiscountType.percentage => DiscountKind.percentage,
        VisitBillingDiscountType.fixed => DiscountKind.fixed,
        VisitBillingDiscountType.none => null,
      };
      if (kind != null) {
        await invoiceRepo.applyInvoiceDiscount(
          invoiceId: invoice.id,
          expectedUpdatedAt: invoice.updatedAt,
          kind: kind,
          value: discountType == VisitBillingDiscountType.percentage
              ? discountValue.round().toString()
              : discountValue.toStringAsFixed(2),
        );
        invoice = await invoiceRepo.getDetail(invoiceId: invoiceId);
      }
    }

    await invoiceRepo.issue(
      invoiceId: invoice.id,
      expectedUpdatedAt: invoice.updatedAt,
    );
    return invoiceRepo.getDetail(invoiceId: invoiceId);
  }

  void _showError(String message) {
    appToast(
      context,
      AppToastInput(message: message, variant: AppToastVariant.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(visitBillingFlowProvider(widget.visitId));
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    final child = switch (billing.step) {
      VisitBillingStep.invoice => VisitInvoiceReviewStep(
        visitId: widget.visitId,
        onBack: () => ref
            .read(visitBillingFlowProvider(widget.visitId).notifier)
            .setStep(VisitBillingStep.services),
        onFinalize: billing.isSubmitting ? null : _handleFinalize,
        isSubmitting: billing.isSubmitting,
      ),
      VisitBillingStep.services => VisitServiceSelectionStep(
        visitId: widget.visitId,
        onBack: _handleBackToReview,
        onContinue: billing.selectedLines.isEmpty
            ? null
            : () => ref
                  .read(visitBillingFlowProvider(widget.visitId).notifier)
                  .setStep(VisitBillingStep.invoice),
      ),
    };

    if (reducedMotion) {
      return child;
    }

    return FadeTransition(opacity: _enterAnimation, child: child);
  }
}
