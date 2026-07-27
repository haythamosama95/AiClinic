import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Bill a visit after documentation review (`/billing/visits/:visitId`).
class VisitBillingPage extends ConsumerStatefulWidget {
  const VisitBillingPage({required this.visitId, super.key});

  final String visitId;

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

  void _backToReview() {
    ref.read(visitBillingFlowProvider(widget.visitId).notifier).reset();
    context.nav.goVisitDocument(widget.visitId);
  }

  void _onCompleted() {
    if (mounted) {
      context.go(AppRoutes.billingInvoices);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

    return docAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (docState) {
        final visit = docState.visit;
        final patientId = visit.patientId;
        final branchId = visit.branchId;
        final patientAsync = ref.watch(patientDetailProvider(patientId));
        final patientName = patientAsync.maybeWhen(
          data: (patient) => patient.fullName,
          orElse: () => 'Patient',
        );

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
                patientId: patientId,
                patientName: patientName,
                branchId: branchId,
                branchName: branchId,
                onBackToReview: _backToReview,
                onCompleted: _onCompleted,
              ),
            ),
          ],
        );
      },
    );
  }
}
