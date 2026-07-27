import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_submission_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_dialog.dart';

/// Post-review billing workflow (web `VisitBillingFlow`).
class VisitBillingFlow extends ConsumerStatefulWidget {
  const VisitBillingFlow({
    required this.visitId,
    required this.patientId,
    required this.patientName,
    required this.branchId,
    required this.branchName,
    this.onBackToReview,
    this.onCompleted,
    super.key,
  });

  final String visitId;
  final String patientId;
  final String patientName;
  final String branchId;
  final String branchName;
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

  Future<void> _showVisitSubmittedDialog({
    required VisitDetail visit,
    VisitBillingInvoicePreview? invoicePreview,
    InvoiceDetail? persistedInvoice,
  }) async {
    final confirmation = VisitSubmissionConfirmation.fromVisit(
      visit: visit,
      patientName: widget.patientName,
      branchName: widget.branchName,
      appointmentStart: visit.visitDate,
      appointmentEnd: visit.visitDate.add(const Duration(minutes: 30)),
      actionAt: DateTime.now().toUtc(),
    );

    Widget? invoiceSummary;
    if (persistedInvoice != null) {
      invoiceSummary = VisitInvoiceSummaryPanel(invoice: persistedInvoice, expanded: true);
    } else if (invoicePreview != null) {
      invoiceSummary = VisitInvoiceSummaryPanel(preview: invoicePreview, expanded: true);
    }

    await VisitSubmittedDialog.show(
      context,
      confirmation: confirmation,
      invoiceSummary: invoiceSummary,
    );
  }

  Future<void> _handleFinalize() async {
    final billing = ref.read(visitBillingFlowProvider(widget.visitId));
    if (billing.isSubmitting || billing.selectedLines.isEmpty) {
      return;
    }

    final permissions = ref.read(permissionServiceProvider);
    final billingNotifier = ref.read(visitBillingFlowProvider(widget.visitId).notifier);

    final outcome = await billingNotifier.finalize(
      canCreateInvoices: permissions.canCreateInvoices(),
      canApplyDiscount: permissions.canApplyDiscount(),
    );

    if (!mounted) {
      return;
    }

    switch (outcome) {
      case VisitFinalizeSucceeded(:final visit, :final invoice):
        if (!permissions.canCreateInvoices()) {
          _showInfo('Visit submitted. No invoice was created because you do not have billing permission.');
        }
        final invoicePreview = billing.invoicePreview;
        billingNotifier.reset();
        await _showVisitSubmittedDialog(
          visit: visit,
          invoicePreview: invoicePreview,
          persistedInvoice: invoice,
        );
        if (mounted) {
          widget.onCompleted?.call();
        }
      case VisitFinalizeInvoiceFailed(:final visit, :final message):
        _showError(
          message,
          action: AppToastAction(label: 'Retry invoice', onPressed: _handleFinalize),
        );
        await _showVisitSubmittedDialog(
          visit: visit,
          invoicePreview: billing.invoicePreview,
        );
      case VisitFinalizeVisitFailed(:final message):
        _showError(message);
    }
  }

  void _showError(String message, {AppToastAction? action}) {
    appToast(
      context,
      AppToastInput(message: message, variant: AppToastVariant.danger, action: action),
    );
  }

  void _showInfo(String message) {
    appToast(
      context,
      AppToastInput(message: message, variant: AppToastVariant.info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(visitBillingFlowProvider(widget.visitId));
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    final child = switch (billing.step) {
      VisitBillingStep.invoice => VisitInvoiceReviewStep(
        visitId: widget.visitId,
        patientName: widget.patientName,
        onBack: () => ref
            .read(visitBillingFlowProvider(widget.visitId).notifier)
            .setStep(VisitBillingStep.services),
        onFinalize: billing.isSubmitting ? null : _handleFinalize,
        isSubmitting: billing.isSubmitting,
      ),
      VisitBillingStep.services => VisitServiceSelectionStep(
        visitId: widget.visitId,
        branchId: widget.branchId,
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
