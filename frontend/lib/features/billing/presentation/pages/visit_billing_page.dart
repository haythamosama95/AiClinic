import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/application/visit_finalize_outcome.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';

/// Bill a visit after documentation review (`/billing/visits/:visitId`).
class VisitBillingPage extends ConsumerStatefulWidget {
  const VisitBillingPage({
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
  final Future<void> Function(
    VisitFinalizeOutcome outcome, {
    VisitBillingInvoicePreview? invoicePreview,
  })?
  onFinalizeOutcome;

  @override
  ConsumerState<VisitBillingPage> createState() => _VisitBillingPageState();
}

class _VisitBillingPageState extends ConsumerState<VisitBillingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(visitBillingFlowProvider(widget.visitId).notifier).beginBilling();
      }
    });
  }

  void _onCompleted() {
    if (mounted) {
      context.go(AppRoutes.billingInvoices);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPageHeader(
          title: 'Bill this visit',
          description: 'Select services performed, review the invoice, then finalize the visit.',
        ),
        const SizedBox(height: AppSpacing.space5),
        Expanded(
          child: VisitBillingFlow(
            visitId: widget.visitId,
            patientId: widget.patientId,
            patientName: widget.patientName,
            branchId: widget.branchId,
            branchName: widget.branchName,
            onFinalizeRequested: widget.onFinalizeRequested,
            onBackToReview: widget.onBackToReview,
            onCompleted: widget.onCompleted ?? _onCompleted,
            onFinalizeOutcome: widget.onFinalizeOutcome,
          ),
        ),
      ],
    );
  }
}
