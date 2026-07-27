import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_service_selection_step.dart';

typedef VisitFinalizeRequestedCallback =
    Future<VisitFinalizeOutcome> Function(VisitFinalizationRequest request);

/// Post-review billing workflow (web `VisitBillingFlow`).
class VisitBillingFlow extends ConsumerStatefulWidget {
  const VisitBillingFlow({
    required this.visitId,
    required this.patientId,
    required this.patientName,
    required this.branchId,
    required this.branchName,
    required this.onFinalizeRequested,
    this.onBackToReview,
    this.onCompleted,
    this.onFinalizeOutcome,
    super.key,
  });

  final String visitId;
  final String patientId;
  final String patientName;
  final String branchId;
  final String branchName;
  final VisitFinalizeRequestedCallback onFinalizeRequested;
  final VoidCallback? onBackToReview;
  final VoidCallback? onCompleted;

  /// Called after finalization with an outcome that should surface a confirmation UI.
  final Future<void> Function(
    VisitFinalizeOutcome outcome, {
    VisitBillingInvoicePreview? invoicePreview,
  })?
  onFinalizeOutcome;

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

  String _localizedFinalizeFailureMessage(String message) {
    if (message == 'visit_finalize_failed') {
      return context.l10n.visitFinalizeFailed;
    }
    return message;
  }

  Future<void> _handleFinalize() async {
    final billing = ref.read(visitBillingFlowProvider(widget.visitId));
    if (billing.isSubmitting || billing.selectedLines.isEmpty) {
      return;
    }

    final permissions = ref.read(permissionServiceProvider);
    final billingNotifier = ref.read(visitBillingFlowProvider(widget.visitId).notifier);
    final l10n = context.l10n;

    billingNotifier.setSubmitting(true);
    VisitFinalizeOutcome outcome;
    try {
      outcome = await widget.onFinalizeRequested(
        VisitFinalizationRequest(
          lines: billing.selectedLines,
          discountType: billing.discountType,
          discountValue: billing.discountValue,
          draftInvoiceId: billing.draftInvoiceId,
        ),
      );
    } finally {
      billingNotifier.setSubmitting(false);
    }

    if (!mounted) {
      return;
    }

    switch (outcome) {
      case VisitFinalizeSucceeded():
        if (!permissions.canCreateInvoices()) {
          _showInfo(l10n.visitBillingSubmittedWithoutInvoicePermission);
        }
        final invoicePreview = billing.invoicePreview;
        billingNotifier.reset();
        await widget.onFinalizeOutcome?.call(outcome, invoicePreview: invoicePreview);
        if (mounted) {
          widget.onCompleted?.call();
        }
      case VisitFinalizeInvoiceFailed(:final message, :final draftInvoiceId):
        billingNotifier.recordInvoiceFailure(draftInvoiceId: draftInvoiceId);
        _showError(
          message,
          action: AppToastAction(label: l10n.visitBillingRetryInvoice, onPressed: _handleFinalize),
        );
        await widget.onFinalizeOutcome?.call(outcome, invoicePreview: billing.invoicePreview);
      case VisitFinalizeVisitFailed(:final message):
        _showError(_localizedFinalizeFailureMessage(message));
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
